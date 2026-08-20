package com.raynlabs.app.billing

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.raynlabs.app.MainActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Native side of the Play Billing bridge (Pigeon [RaynBilling]).
 *
 * Scope is deliberately narrow: connect, query offers, launch the purchase, and
 * list active purchases. Everything else — verifying the purchase, importing the
 * `rayn://` link, session/account state — lives in Dart. Crucially this handler
 * **never acknowledges**: the backend acknowledges during `POST /iap/google/verify`
 * (IAP-CLIENT-INTEGRATION.md), and the bridge exposes no way to do so, which makes
 * "client never acknowledges" structural rather than a convention.
 *
 * Play's asynchronous purchase events (`PurchasesUpdatedListener`,
 * `onBillingServiceDisconnected`) are pushed up to Dart through [RaynBillingEvents]
 * on the main thread. Purchase tokens are treated as credentials — never logged.
 */
class RaynBillingHandler : FlutterPlugin, RaynBilling {

    private companion object {
        const val TAG = "ANDROID/RaynBilling"
    }

    private val main = Handler(Looper.getMainLooper())

    private var context: Context? = null
    private var events: RaynBillingEvents? = null
    private var billingClient: BillingClient? = null

    /** offerToken -> the ProductDetails it belongs to, cached from [queryOffers]
     *  so [launchPurchase] can rebuild BillingFlowParams (which needs the full
     *  ProductDetails, not just the token). Cleared on each fresh query. */
    private val offerIndex = mutableMapOf<String, ProductDetails>()

    // ---- FlutterPlugin lifecycle ----

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        events = RaynBillingEvents(binding.binaryMessenger)
        RaynBilling.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        RaynBilling.setUp(binding.binaryMessenger, null)
        endConnection()
        events = null
        context = null
    }

    // Play delivers updates here (sometimes long after launch, e.g. PENDING->PURCHASED).
    // Marshal to the main thread before crossing the Pigeon FlutterApi.
    private val purchasesListener = PurchasesUpdatedListener { result, purchases ->
        val mapped = purchases?.map { it.toRayn() } ?: emptyList()
        main.post { events?.onPurchasesUpdated(mapped, result.responseCode.toLong()) {} }
    }

    // ---- RaynBilling (Dart -> Kotlin) ----

    override fun connect(callback: (Result<BillingConnState>) -> Unit) {
        val ctx = context
        if (ctx == null) {
            main.post { callback(Result.success(BillingConnState.UNAVAILABLE)) }
            return
        }
        billingClient?.let {
            if (it.isReady) {
                main.post { callback(Result.success(BillingConnState.CONNECTED)) }
                return
            }
        }
        val client = billingClient ?: BillingClient.newBuilder(ctx)
            .setListener(purchasesListener)
            .enablePendingPurchases(
                PendingPurchasesParams.newBuilder().enableOneTimeProducts().build(),
            )
            .build()
            .also { billingClient = it }

        // onBillingSetupFinished fires once per startConnection; guard anyway so a
        // stray double-callback can never reply twice over the Pigeon channel.
        val replied = AtomicBoolean(false)
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                val state = when (billingResult.responseCode) {
                    BillingClient.BillingResponseCode.OK -> BillingConnState.CONNECTED
                    BillingClient.BillingResponseCode.BILLING_UNAVAILABLE -> BillingConnState.DISABLED
                    else -> BillingConnState.UNAVAILABLE
                }
                if (replied.compareAndSet(false, true)) {
                    main.post { callback(Result.success(state)) }
                }
            }

            override fun onBillingServiceDisconnected() {
                main.post { events?.onBillingDisconnected {} }
            }
        })
    }

    override fun queryOffers(productId: String, callback: (Result<List<RaynOffer>>) -> Unit) {
        val client = billingClient
        if (client == null || !client.isReady) {
            main.post { callback(Result.success(emptyList())) }
            return
        }
        val product = QueryProductDetailsParams.Product.newBuilder()
            .setProductId(productId)
            .setProductType(BillingClient.ProductType.SUBS)
            .build()
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(listOf(product))
            .build()

        client.queryProductDetailsAsync(params) { result, queryResult ->
            if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                Log.w(TAG, "queryOffers failed: ${result.responseCode}")
                main.post { callback(Result.success(emptyList())) }
                return@queryProductDetailsAsync
            }
            val offers = mutableListOf<RaynOffer>()
            offerIndex.clear()
            for (details in queryResult.productDetailsList) {
                val subOffers = details.subscriptionOfferDetails ?: continue
                for (offer in subOffers) {
                    val phases = offer.pricingPhases.pricingPhaseList
                    if (phases.isEmpty()) continue
                    offerIndex[offer.offerToken] = details
                    // The recurring (last) phase is the real subscription price; an
                    // earlier zero-price phase means this offer leads with a trial.
                    val recurring = phases.last()
                    offers.add(
                        RaynOffer(
                            basePlanId = offer.basePlanId,
                            offerId = offer.offerId,
                            offerToken = offer.offerToken,
                            formattedPrice = recurring.formattedPrice,
                            priceAmountMicros = recurring.priceAmountMicros,
                            priceCurrencyCode = recurring.priceCurrencyCode,
                            billingPeriodIso = recurring.billingPeriod,
                            isTrial = phases.any { it.priceAmountMicros == 0L },
                        ),
                    )
                }
            }
            main.post { callback(Result.success(offers)) }
        }
    }

    override fun launchPurchase(offerToken: String, obfuscatedAccountId: String): LaunchResult {
        val client = billingClient
        if (client == null || !client.isReady) {
            return LaunchResult(BillingClient.BillingResponseCode.SERVICE_DISCONNECTED.toLong(), "billing not connected")
        }
        val details = offerIndex[offerToken]
            ?: return LaunchResult(BillingClient.BillingResponseCode.DEVELOPER_ERROR.toLong(), "unknown offer token; query offers first")
        val activity = try {
            MainActivity.instance
        } catch (e: Exception) {
            return LaunchResult(BillingClient.BillingResponseCode.ERROR.toLong(), "no foreground activity")
        }

        val productParams = BillingFlowParams.ProductDetailsParams.newBuilder()
            .setProductDetails(details)
            .setOfferToken(offerToken)
            .build()
        val builder = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(productParams))
        // The account binding the backend verifies against (raw lowercase user UUID).
        if (obfuscatedAccountId.isNotEmpty()) {
            builder.setObfuscatedAccountId(obfuscatedAccountId)
        }
        val result = client.launchBillingFlow(activity, builder.build())
        return LaunchResult(result.responseCode.toLong(), result.debugMessage)
    }

    override fun queryActivePurchases(callback: (Result<List<RaynPurchase>>) -> Unit) {
        val client = billingClient
        if (client == null || !client.isReady) {
            main.post { callback(Result.success(emptyList())) }
            return
        }
        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.SUBS)
            .build()
        client.queryPurchasesAsync(params) { result, purchases ->
            val mapped = if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                purchases.map { it.toRayn() }
            } else {
                Log.w(TAG, "queryActivePurchases failed: ${result.responseCode}")
                emptyList()
            }
            main.post { callback(Result.success(mapped)) }
        }
    }

    /**
     * Deliberate no-op on Play.
     *
     * The method exists for Apple, where StoreKit redelivers an unfinished
     * transaction forever and finishing it is how the client confirms
     * delivery. Play has no equivalent: the only thing that would settle a
     * purchase here is `acknowledgePurchase`, and the BACKEND does that during
     * verify. Acknowledging from the client would double-acknowledge, so this
     * stays empty on purpose — see the invariant in pigeons/rayn_billing.dart.
     */
    override fun finishPurchase(purchaseToken: String) = Unit

    override fun endConnection() {
        billingClient?.endConnection()
        billingClient = null
        offerIndex.clear()
    }

    private fun Purchase.toRayn(): RaynPurchase = RaynPurchase(
        purchaseToken = purchaseToken,
        productId = products.firstOrNull() ?: "",
        state = when (purchaseState) {
            Purchase.PurchaseState.PURCHASED -> RaynPurchaseState.PURCHASED
            Purchase.PurchaseState.PENDING -> RaynPurchaseState.PENDING
            else -> RaynPurchaseState.UNSPECIFIED
        },
        isAcknowledged = isAcknowledged,
    )
}
