//
//  RaynBillingHandler.swift
//  Runner
//
//  StoreKit 2 host for the RaynBilling Pigeon contract — the iOS twin of
//  android/app/src/main/kotlin/com/raynlabs/app/billing/RaynBillingHandler.kt.
//
//  Design (pigeons/rayn_billing.dart, APPLE-IAP-CLIENT-INTEGRATION.md):
//    * Dart owns verify / import / session / UI. This file does ONLY the
//      StoreKit dance and persists nothing.
//    * Entitlement follows the BACKEND, never a local transaction. Nothing here
//      grants access; it reports what StoreKit says and hands ids to Dart.
//    * `finishPurchase` is called by Dart only after `POST /iap/apple/verify`
//      returns 200. Finishing earlier would throw away a purchase the backend
//      never recorded.
//    * Response codes are Play's integers on purpose (0 OK, 1 USER_CANCELED,
//      6 ERROR) so the shared Dart layer needs no per-store branching. Play's
//      7 ITEM_ALREADY_OWNED has no StoreKit equivalent — buying while already
//      subscribed returns the existing transaction, which verifies idempotently.
//
//  Purchase ids are treated as credentials — never logged.
//

import Flutter
import Foundation
import StoreKit

public class RaynBillingHandler: NSObject, FlutterPlugin, RaynBilling {

    public static let name = "\(Bundle.main.serviceIdentifier)/billing"

    /// The Play `BillingResponseCode` values the Dart layer branches on.
    private enum ResponseCode {
        static let ok: Int64 = 0
        static let userCanceled: Int64 = 1
        static let error: Int64 = 6
    }

    /// Base-plan suffixes, in the same order and spelling as Dart's `_planOrder`
    /// (purchase_notifier.dart). Play models one product with three base plans;
    /// the App Store models three products in one subscription group, so the
    /// group id we are handed is expanded into `<group>_<basePlanId>`.
    ///
    /// If App Store Connect ever diverges from that convention,
    /// `Product.products(for:)` returns fewer products than asked for and the
    /// paywall shows its "unavailable" state — a loud failure, not a silent one.
    private static let basePlanIds = ["monthly", "quarter", "annual"]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = RaynBillingHandler()
        instance.events = RaynBillingEvents(binaryMessenger: registrar.messenger())
        RaynBillingSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
        // Started here, at launch, rather than on `connect()`: StoreKit can
        // deliver a renewal or an Ask-to-Buy approval before any Flutter UI
        // exists, and an event delivered with no Dart receiver attached is lost.
        // Events raised before Dart is listening are buffered — see `emit`.
        instance.startTransactionListener()
    }

    private var events: RaynBillingEvents?

    /// `offerToken` (on Apple, the product id) -> the `Product` needed to buy.
    /// Populated by `queryOffers`; never persisted.
    private var productIndex: [String: Product] = [:]

    /// The long-lived `Transaction.updates` observer. Nil only before `register`
    /// and after `endConnection`.
    private var updatesTask: Task<Void, Never>?

    /// Events raised before Dart attached a `RaynBillingEvents` receiver.
    /// Drained by the first `connect()`, which is the point at which the Dart
    /// side is known to be listening.
    private var pending: [(purchases: [RaynPurchase], responseCode: Int64)] = []
    private var dartReady = false

    // MARK: - RaynBilling (Dart -> native)
    //
    // Internal, not public: Pigeon emits `RaynBilling` and its models as internal
    // types, and a public method cannot expose an internal type in its
    // signature. `register`/`name` above stay public because FlutterPlugin is a
    // public protocol.

    func connect(completion: @escaping (Result<BillingConnState, Error>) -> Void) {
        startTransactionListener()
        // There is no connection to establish. The only thing that can make
        // purchasing impossible on a healthy device is a payment restriction
        // (Screen Time), which is what `canMakePayments` reports.
        let state: BillingConnState = AppStore.canMakePayments ? .connected : .disabled
        onMain {
            self.dartReady = true
            self.flushPending()
            completion(.success(state))
        }
    }

    func queryOffers(productId: String, completion: @escaping (Result<[RaynOffer], Error>) -> Void) {
        let ids = Set(Self.basePlanIds.map { "\(productId)_\($0)" })
        Task {
            let products: [Product]
            do {
                products = try await Product.products(for: ids)
            } catch {
                // Match the Kotlin host: a query failure is an empty list, never
                // an error across the channel. Dart renders "unavailable".
                NSLog("[RaynBilling] queryOffers failed")
                self.onMain { completion(.success([])) }
                return
            }

            var offers: [RaynOffer] = []
            for product in products {
                guard let subscription = product.subscription else { continue }
                offers.append(
                    RaynOffer(
                        basePlanId: Self.basePlanId(of: product.id, group: productId),
                        // Apple applies an eligible introductory offer at
                        // purchase time rather than exposing it as a separately
                        // purchasable offer, so there is exactly one per product.
                        offerId: nil,
                        offerToken: product.id,
                        formattedPrice: product.displayPrice,
                        priceAmountMicros: Self.micros(product.price),
                        priceCurrencyCode: Self.currencyCode(of: product),
                        billingPeriodIso: Self.iso8601(subscription.subscriptionPeriod),
                        // No introductory offer is configured in App Store
                        // Connect, so nothing here ever leads with a free phase.
                        // Reporting a trial we cannot deliver would be a lie on
                        // the paywall, so this stays false until one exists.
                        isTrial: false
                    )
                )
            }

            let resolved = offers
            self.onMain {
                self.productIndex = Dictionary(
                    products.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                completion(.success(resolved))
            }
        }
    }

    func launchPurchase(offerToken: String, obfuscatedAccountId: String) throws -> LaunchResult {
        guard let product = productIndex[offerToken] else {
            return LaunchResult(responseCode: ResponseCode.error, debugMessage: "unknown offer token; query offers first")
        }

        // The RouteKey user id, verbatim. Apple requires a UUID here; if the
        // stored value is missing or malformed we omit the option rather than
        // invent one — verify still works (the session identifies the user), it
        // just costs the backend its pre-verify attribution.
        var options: Set<Product.PurchaseOption> = []
        if let accountToken = UUID(uuidString: obfuscatedAccountId) {
            options.insert(.appAccountToken(accountToken))
        } else {
            NSLog("[RaynBilling] appAccountToken omitted: not a UUID")
        }

        // Not @async in the contract: this reports only that the sheet opened,
        // exactly as Play's `launchBillingFlow` does. The purchase itself comes
        // back through RaynBillingEvents.
        Task { await self.purchase(product, options: options) }
        return LaunchResult(responseCode: ResponseCode.ok)
    }

    func queryActivePurchases(completion: @escaping (Result<[RaynPurchase], Error>) -> Void) {
        Task {
            // `currentEntitlements` covers reinstall and a new device;
            // `unfinished` covers a verify that was interrupted after payment.
            // Dart needs both. An entitlement is assumed settled unless it also
            // turns up unfinished, in which case the second pass corrects it —
            // and adds anything unfinished that is no longer an entitlement.
            var byId: [UInt64: RaynPurchase] = [:]
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result else { continue }
                byId[transaction.id] = RaynBillingHandler.map(transaction, isFinished: true)
            }
            for await result in Transaction.unfinished {
                guard case .verified(let transaction) = result else { continue }
                byId[transaction.id] = RaynBillingHandler.map(transaction, isFinished: false)
            }

            let purchases = Array(byId.values)
            self.onMain { completion(.success(purchases)) }
        }
    }

    func finishPurchase(purchaseToken: String) throws {
        guard let id = UInt64(purchaseToken) else {
            NSLog("[RaynBilling] finishPurchase: id is not a transaction id")
            return
        }
        Task {
            for await result in Transaction.unfinished {
                guard case .verified(let transaction) = result, transaction.id == id else { continue }
                await transaction.finish()
                return
            }
        }
    }

    func endConnection() throws {
        updatesTask?.cancel()
        updatesTask = nil
        productIndex.removeAll()
        dartReady = false
        pending.removeAll()
    }

    // MARK: - Purchase flow

    private func purchase(_ product: Product, options: Set<Product.PurchaseOption>) async {
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase(options: options)
        } catch StoreKitError.userCancelled {
            emit([], ResponseCode.userCanceled)
            return
        } catch {
            NSLog("[RaynBilling] purchase failed")
            emit([], ResponseCode.error)
            return
        }

        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                // StoreKit could not verify Apple's own signature. Never send an
                // unverified transaction to the backend.
                NSLog("[RaynBilling] purchase result failed local verification")
                emit([], ResponseCode.error)
                return
            }
            // Deliberately NOT finished here. Dart finishes it after the backend
            // has recorded the purchase; until then StoreKit keeps redelivering.
            emit([Self.map(transaction, isFinished: false)], ResponseCode.ok)

        case .pending:
            // Ask-to-Buy or SCA: approved later, and it arrives on
            // Transaction.updates. There is no transaction yet, so synthesise
            // the PENDING shape the Dart layer already understands.
            emit(
                [
                    RaynPurchase(
                        purchaseToken: "",
                        productId: product.id,
                        state: .pending,
                        isAcknowledged: false
                    )
                ],
                ResponseCode.ok
            )

        case .userCancelled:
            emit([], ResponseCode.userCanceled)

        @unknown default:
            emit([], ResponseCode.error)
        }
    }

    /// Renewals, Ask-to-Buy approvals, purchases made on another device, and
    /// anything that completed while the app was not running. Mandatory, and
    /// runs for the whole app lifetime (APPLE-IAP-CLIENT-INTEGRATION.md §5.5).
    private func startTransactionListener() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self, case .verified(let transaction) = result else { continue }
                self.emit([RaynBillingHandler.map(transaction, isFinished: false)], ResponseCode.ok)
            }
        }
    }

    // MARK: - Event plumbing

    /// Push a purchase update to Dart, buffering it if Dart is not listening yet.
    private func emit(_ purchases: [RaynPurchase], _ responseCode: Int64) {
        onMain {
            guard self.dartReady, let events = self.events else {
                self.pending.append((purchases, responseCode))
                return
            }
            events.onPurchasesUpdated(purchases: purchases, responseCode: responseCode) { _ in }
        }
    }

    private func flushPending() {
        guard let events = events, !pending.isEmpty else { return }
        let queued = pending
        pending.removeAll()
        for item in queued {
            events.onPurchasesUpdated(purchases: item.purchases, responseCode: item.responseCode) { _ in }
        }
    }

    /// Everything crossing the Pigeon boundary goes through the main thread, as
    /// on Android. StoreKit work happens on whatever executor it likes.
    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    // MARK: - Mapping

    private static func map(_ transaction: Transaction, isFinished: Bool) -> RaynPurchase {
        RaynPurchase(
            // A JSON string on the wire: Transaction.id is a UInt64, and the
            // backend rejects it encoded as a number.
            purchaseToken: String(transaction.id),
            productId: transaction.productID,
            // Every transaction StoreKit hands us has been paid for; `pending`
            // exists only as the synthesised Ask-to-Buy case above.
            state: .purchased,
            // On Apple this means "already settled": we finish a transaction
            // only after a backend 200, so a finished one is already bound.
            isAcknowledged: isFinished
        )
    }

    private static func basePlanId(of productId: String, group: String) -> String {
        let prefix = "\(group)_"
        guard productId.hasPrefix(prefix) else { return productId }
        return String(productId.dropFirst(prefix.count))
    }

    private static func micros(_ price: Decimal) -> Int64 {
        let scaled = NSDecimalNumber(decimal: price * 1_000_000)
            .rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            ))
        return scaled.int64Value
    }

    private static func currencyCode(of product: Product) -> String {
        if #available(iOS 16.0, *) {
            return product.priceFormatStyle.currencyCode
        }
        return product.priceFormatStyle.locale.currencyCode ?? "USD"
    }

    /// The recurring billing period, in the ISO-8601 form Play returns and
    /// `periodMonths` (plan_card.dart) parses.
    private static func iso8601(_ period: Product.SubscriptionPeriod) -> String {
        let n = period.value
        switch period.unit {
        case .day: return "P\(n)D"
        case .week: return "P\(n)W"
        case .month: return "P\(n)M"
        case .year: return "P\(n)Y"
        @unknown default: return "P\(n)M"
        }
    }
}
