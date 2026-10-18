import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:hiddify/bootstrap.dart';
import 'package:hiddify/core/model/environment.dart';

Future<void> main(List<String> args) async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // debugPaintSizeEnabled = true;

  // Bar colours are not set anywhere: MainActivity makes the bars transparent,
  // and the app's root region sets only icon brightness (raynSystemBarStyle).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  return await lazyBootstrap(widgetsBinding, Environment.dev, args: args);
}
