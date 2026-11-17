import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/config.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

/// Page du site affichée dans l'application (dossier chauffeur, paiement, support, pages légales).
///
/// - [path] : page interne du site, ouverte déjà connectée grâce à un lien à usage unique ;
/// - [url] : adresse complète (page de paiement ChapChap, page publique) ;
/// - [closeOn] : chemin qui ferme l'écran dès qu'il est atteint (retour de paiement, fin du dossier).
class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.title, this.path, this.url, this.closeOn, this.signedIn = true});

  final String title;
  final String? path;
  final String? url;
  final String? closeOn;
  final bool signedIn;

  static Future<bool?> open(BuildContext context, {required String title, String? path, String? url, String? closeOn, bool signedIn = true}) =>
      Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => WebPage(title: title, path: path, url: url, closeOn: closeOn, signedIn: signedIn),
      ));

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final WebViewController _web;
  int _progress = 0;
  String? _error;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Y.brume)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageStarted: (url) => _checkClose(url),
        onNavigationRequest: (req) {
          final uri = Uri.tryParse(req.url);
          if (uri == null) return NavigationDecision.prevent;
          if (_checkClose(req.url)) return NavigationDecision.prevent;
          if (uri.scheme != 'http' && uri.scheme != 'https') {
            launchUrl(uri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          }
          // WhatsApp et cartes : application dédiée
          if (uri.host.endsWith('wa.me') || uri.host.contains('whatsapp.com') || uri.host.startsWith('maps.google')) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) setState(() => _error = 'La page n\'a pas pu être chargée. Vérifiez votre connexion.');
        },
      ));
    _setupFiles();
    _load();
  }

  /// Champs « fichier » des formulaires (pièces du dossier chauffeur) : photo, galerie ou PDF.
  void _setupFiles() {
    final platform = _web.platform;
    if (platform is AndroidWebViewController) {
      platform.setOnShowFileSelector((params) async {
        final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Prendre une photo'), onTap: () => Navigator.pop(ctx, 'camera')),
              ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choisir dans la galerie'), onTap: () => Navigator.pop(ctx, 'gallery')),
              if (params.acceptTypes.isEmpty || params.acceptTypes.any((t) => t.contains('pdf') || t == '*/*'))
                ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: const Text('Fichier PDF'), onTap: () => Navigator.pop(ctx, 'pdf')),
              const SizedBox(height: 8),
            ]),
          ),
        );
        try {
          if (choice == 'camera' || choice == 'gallery') {
            final x = await ImagePicker().pickImage(
              source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
              maxWidth: 2200, maxHeight: 2200, imageQuality: 85,
            );
            return x == null ? <String>[] : [Uri.file(x.path).toString()];
          }
          if (choice == 'pdf') {
            final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'PDF', extensions: ['pdf'], mimeTypes: ['application/pdf'])]);
            return f == null ? <String>[] : [Uri.file(f.path).toString()];
          }
        } catch (_) {
          if (mounted) toast(context, 'Impossible d\'accéder au fichier. Vérifiez les autorisations.', error: true);
        }
        return <String>[];
      });
    }
  }

  Future<void> _load() async {
    if (widget.url == null && widget.path == null) {
      setState(() => _error = 'Cette page n\'est pas disponible pour le moment.');
      return;
    }
    setState(() => _error = null);
    try {
      final ua = await _web.getUserAgent();
      await _web.setUserAgent('${ua ?? (defaultTargetPlatform == TargetPlatform.iOS ? 'iPhone' : 'Android')} ${AppConfig.userAgentMarker}');
    } catch (_) {}
    try {
      String target;
      if (widget.url != null) {
        target = widget.url!;
      } else if (widget.signedIn) {
        target = await context.read<Session>().webLink(widget.path!);
      } else {
        target = '${AppConfig.baseUrl}${widget.path}';
      }
      await _web.loadRequest(Uri.parse(target));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  bool _checkClose(String url) {
    final close = widget.closeOn;
    if (close == null || _closed) return false;
    final uri = Uri.tryParse(url);
    if (uri != null && uri.path.startsWith(close) && uri.host == Uri.parse(AppConfig.baseUrl).host) {
      _closed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _web.canGoBack()) {
          await _web.goBack();
        } else {
          nav.pop(false);
        }
      },
      child: Scaffold(
        backgroundColor: Y.brume,
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Fermer', onPressed: () => Navigator.of(context).pop(false)),
          actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Actualiser', onPressed: () => _web.reload())],
          bottom: _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(value: _progress / 100, minHeight: 3, color: Y.braise, backgroundColor: Colors.transparent),
                )
              : null,
        ),
        body: _error != null ? RetryView(message: _error!, onRetry: _load) : WebViewWidget(controller: _web),
      ),
    );
  }
}
