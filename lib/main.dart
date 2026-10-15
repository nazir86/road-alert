import 'supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(const RoadAlertApp());
}

const primary = Color(0xFF175CD3);
const ink = Color(0xFF16243A);
const canvas = Color(0xFFF2F6FC);
const accent = Color(0xFF0FAE9B);
const kinds = ['Nid-de-poule', 'Route fissurée', 'Route inondée', 'Éboulement', 'Route coupée', 'Autre'];
const statuses = ['Nouveau', 'En cours', 'Résolu'];
const levels = ['Faible', 'Moyenne', 'Élevée', 'Critique'];

class RoadAlertApp extends StatelessWidget {
  const RoadAlertApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ROAD ALERT',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Roboto',
          colorScheme: ColorScheme.fromSeed(seedColor: primary, surface: Colors.white),
          scaffoldBackgroundColor: canvas,
          appBarTheme: const AppBarTheme(elevation: 0, backgroundColor: Colors.white, foregroundColor: ink),
          cardTheme: CardThemeData(color: Colors.white, elevation: 0,
            margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          inputDecorationTheme: InputDecorationTheme(
            filled: true, fillColor: const Color(0xFFF9FBFE),
            contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: Color(0xFFDAE3F1))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: Color(0xFFDAE3F1))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: primary, width: 1.5)),
          ),
          filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
            backgroundColor: primary, foregroundColor: Colors.white, minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
          outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 49), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
        ),
        home: const RoadHome(),
      );
}

class RoadHome extends StatefulWidget {
  const RoadHome({super.key});
  @override
  State<RoadHome> createState() => _RoadHomeState();
}

class _RoadHomeState extends State<RoadHome> {
  final MapController mapController = MapController();
  List<Map<String, dynamic>> reports = [];
  bool loading = true;
  int page = 0;
  int formId = 0;
  Map<String, dynamic>? editing;
  String search = '';
  String filter = 'Tous';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final data = p.getString('road_alert_v2');
      if (data != null) {
        reports = (jsonDecode(data) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (e) {
      debugPrint('Lecture stockage: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> persist() async {
    final p = await SharedPreferences.getInstance();
    if (!await p.setString('road_alert_v2', jsonEncode(reports))) {
      throw Exception('Stockage local indisponible');
    }
  }

  void newReport() => setState(() {
        editing = null;
        formId++;
        page = 1;
      });

  void editReport(Map<String, dynamic> report) => setState(() {
        editing = Map<String, dynamic>.from(report);
        formId++;
        page = 1;
      });

  Future<void> save(Map<String, dynamic> report) async {
    final previous = reports.map((e) => Map<String, dynamic>.from(e)).toList();
    final record = Map<String, dynamic>.from(report);
    if (editing == null) {
      record['id'] = DateTime.now().microsecondsSinceEpoch.toString();
      record['date'] = DateTime.now().toIso8601String();
      reports.insert(0, record);
    } else {
      record['id'] = editing!['id'];
      record['date'] = editing!['date'];
      final index = reports.indexWhere((e) => e['id'] == record['id']);
      if (index >= 0) reports[index] = record;
    }
    try {
      await persist();
    } catch (e) {
      reports = previous;
      rethrow;
    }
    if (!mounted) return;
    setState(() {
      editing = null;
      page = 2;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Signalement enregistré')),
    );
  }

  Future<void> remove(Map<String, dynamic> record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer ce signalement ?'),
        content: Text('${record['titre']}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    final previous = List<Map<String, dynamic>>.from(reports);
    reports.removeWhere((r) => r['id'] == record['id']);
    try {
      await persist();
    } catch (e) {
      reports = previous;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() {});
  }

  LatLng? position(Map<String, dynamic> report) {
    final lat = double.tryParse('${report['lat'] ?? ''}'.replaceAll(',', '.'));
    final lon = double.tryParse('${report['lon'] ?? ''}'.replaceAll(',', '.'));
    if (lat == null || lon == null || lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    return LatLng(lat, lon);
  }

  void onMap(Map<String, dynamic> report) {
    if (position(report) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoutez les coordonnées GPS à ce signalement.')),
      );
      return;
    }
    setState(() => page = 3);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try { mapController.move(position(report)!, 15); } catch (_) { /* Carte en cours de montage */ }
    });
  }

  void details(Map<String, dynamic> record) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${record['titre']}'),
        content: SizedBox(
          width: 470,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if ('${record['photo'] ?? ''}'.isNotEmpty) ...[
                Image.memory(base64Decode(record['photo'] as String), height: 180, fit: BoxFit.cover),
                const SizedBox(height: 12),
              ],
              Text('Type : ${record['type']}'),
              Text('Gravité : ${record['gravite']}'),
              Text('Statut : ${record['statut']}'),
              Text('Lieu : ${record['lieu']}'),
              Text('Coordonnées : ${record['lat']}, ${record['lon']}'),
              const SizedBox(height: 10),
              Text('${record['description']}'),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
          TextButton(onPressed: () { Navigator.pop(c); onMap(record); }, child: const Text('Carte')),
          FilledButton(onPressed: () { Navigator.pop(c); editReport(record); }, child: const Text('Modifier')),
        ],
      ),
    );
  }

  Color severityColor(String? severity) => switch (severity) {
    'Critique' => const Color(0xFFE5484D),
    'Élevée' => const Color(0xFFF59E0B),
    'Moyenne' => primary,
    _ => accent,
  };

  Widget reportCard(Map<String, dynamic> record) {
    final raw = '${record['photo'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => details(record),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 62, height: 66,
                  child: raw.isEmpty
                      ? ColoredBox(color: const Color(0xFFE9F1FF), child: Icon(Icons.warning_amber_rounded, color: severityColor('${record['gravite']}'), size: 32))
                      : Image.memory(base64Decode(raw), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${record['titre']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, color: ink, fontSize: 15)),
                const SizedBox(height: 5),
                Text('${record['lieu']} • ${record['type']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF66738B))),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 5, children: [
                  RoadPill(label: '${record['statut']}', color: '${record['statut']}' == 'Résolu' ? accent : ('${record['statut']}' == 'En cours' ? const Color(0xFF8959CF) : primary)),
                  RoadPill(label: '${record['gravite']}', color: severityColor('${record['gravite']}')),
                ]),
              ])),
              PopupMenuButton<String>(tooltip: 'Actions', icon: const Icon(Icons.more_vert, color: Color(0xFF637087)),
                onSelected: (v) {
                  if (v == 'Voir') details(record);
                  if (v == 'Modifier') editReport(record);
                  if (v == 'Carte') onMap(record);
                  if (v == 'Supprimer') remove(record);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'Voir', child: ListTile(leading: Icon(Icons.visibility_outlined), title: Text('Consulter'), dense: true)),
                  const PopupMenuItem(value: 'Modifier', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Modifier'), dense: true)),
                  const PopupMenuItem(value: 'Carte', child: ListTile(leading: Icon(Icons.map_outlined), title: Text('Voir sur la carte'), dense: true)),
                  const PopupMenuItem(value: 'Supprimer', child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Supprimer'), dense: true)),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget stat(String name, int number, IconData icon, Color color) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 23, color: color)),
        const Spacer(),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: number.toDouble()), duration: const Duration(milliseconds: 650),
          builder: (context, value, child) => Text('${value.round()}',
            style: const TextStyle(fontSize: 31, fontWeight: FontWeight.w900, color: ink))),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF6F7C91), fontWeight: FontWeight.w600)),
      ]),
    ),
  );

  Widget dashboard() => ListView(padding: const EdgeInsets.all(20), children: [
    Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF123B80), primary, Color(0xFF3486F6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 16,
        children: [
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TABLEAU DE BORD', style: TextStyle(color: Color(0xFFCBE1FF), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2)),
            SizedBox(height: 8),
            Text('Des routes plus sûres,\nensemble.', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, height: 1.15)),
            SizedBox(height: 7),
            Text('Suivez et signalez les dégradations routières.', style: TextStyle(color: Color(0xFFE0EBFF))),
          ]),
          FilledButton.icon(onPressed: newReport, style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: primary),
            icon: const Icon(Icons.add_circle_outline), label: const Text('Nouveau signalement')),
        ],
      ),
    ),
    const SizedBox(height: 24),
    const Text('Vue d’ensemble', style: TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w900)),
    const SizedBox(height: 12),
    LayoutBuilder(builder: (c, box) => GridView.count(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: box.maxWidth >= 810 ? 4 : 2,
      childAspectRatio: box.maxWidth >= 810 ? 1.58 : (box.maxWidth >= 420 ? 1.6 : 1.08),
      crossAxisSpacing: 12, mainAxisSpacing: 12,
      children: [
        stat('Signalements', reports.length, Icons.assignment_outlined, primary),
        stat('Nouveaux', reports.where((r) => r['statut'] == 'Nouveau').length, Icons.notification_important_outlined, const Color(0xFFF59E0B)),
        stat('En cours', reports.where((r) => r['statut'] == 'En cours').length, Icons.schedule_outlined, const Color(0xFF8959CF)),
        stat('Résolus', reports.where((r) => r['statut'] == 'Résolu').length, Icons.verified_outlined, accent),
      ],
    )),
    const SizedBox(height: 25),
    Row(children: [
      const Expanded(child: Text('Signalements récents', style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w900))),
      TextButton.icon(onPressed: () => setState(() => page = 2), icon: const Icon(Icons.arrow_forward, size: 16), label: const Text('Tout voir')),
    ]),
    const SizedBox(height: 9),
    if (reports.isEmpty) const RoadEmpty(icon: Icons.check_circle_outline, title: 'Aucun signalement', subtitle: 'Commencez par signaler une dégradation.'),
    ...reports.take(5).map(reportCard),
  ]);

  Widget listing() {
    final results = reports.where((r) {
      final content = '${r['titre']} ${r['lieu']} ${r['type']} ${r['description']}'.toLowerCase();
      return content.contains(search.toLowerCase()) && (filter == 'Tous' || r['statut'] == filter);
    }).toList();
    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Signalements', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: ink)),
          Text('Recherchez, modifiez et suivez les incidents.', style: TextStyle(color: Color(0xFF66738B))),
        ])),
        IconButton.filled(tooltip: 'Ajouter', onPressed: newReport, icon: const Icon(Icons.add)),
      ]),
      const SizedBox(height: 19),
      LayoutBuilder(builder: (ctx, constraints) => constraints.maxWidth > 620
          ? Row(children: [
              Expanded(flex: 3, child: TextField(decoration: const InputDecoration(hintText: 'Rechercher un lieu, type ou titre...', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => search = v))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: statusFilter()),
            ])
          : Column(children: [
              TextField(decoration: const InputDecoration(hintText: 'Rechercher...', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => search = v)),
              const SizedBox(height: 10), statusFilter(),
            ])),
      const SizedBox(height: 17),
      Text('${results.length} résultat(s)', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF66738B))),
      const SizedBox(height: 12),
      if (results.isEmpty) const RoadEmpty(icon: Icons.search_off_rounded, title: 'Aucun résultat', subtitle: 'Essayez une autre recherche ou un autre filtre.'),
      ...results.map(reportCard),
    ]);
  }

  Widget statusFilter() => DropdownButtonFormField<String>(
    key: ValueKey(filter), initialValue: filter,
    decoration: const InputDecoration(labelText: 'Statut'),
    items: ['Tous', ...statuses].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
    onChanged: (v) => setState(() => filter = v ?? 'Tous'),
  );

  Widget mapPage() {
    final markers = reports.where((r) => position(r) != null).map((r) {
      return Marker(
        point: position(r)!, width: 45, height: 50,
        child: Tooltip(
          message: '${r['titre']} — ${r['statut']}',
          child: IconButton(
            onPressed: () => details(r),
            icon: const Icon(Icons.location_on, color: Colors.red, size: 38),
          ),
        ),
      );
    }).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        const Icon(Icons.map_outlined, color: primary), const SizedBox(width: 10),
        Expanded(child: Text('Carte des signalements', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: ink))),
        RoadPill(label: '${markers.length} localisé(s)', color: primary),
      ])),
      Expanded(child: FlutterMap(
        mapController: mapController,
        options: const MapOptions(initialCenter: LatLng(-18.8792, 47.5079), initialZoom: 12),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.road_alert',
          ),
          MarkerLayer(markers: markers),
          const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
        ],
      )),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    final current = loading ? const Center(child: CircularProgressIndicator())
        : page == 0 ? dashboard()
        : page == 1 ? ReportForm(key: ValueKey(formId), original: editing, onSave: save)
        : page == 2 ? listing() : mapPage();
    void select(int index) {
      if (index == 1) { newReport(); } else { setState(() => page = index); }
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.route_rounded, color: Colors.white, size: 24)),
          const SizedBox(width: 10),
          const Text('ROAD ', style: TextStyle(fontWeight: FontWeight.w900, color: ink, letterSpacing: 0.5)),
          const Text('ALERT', style: TextStyle(fontWeight: FontWeight.w900, color: primary, letterSpacing: 0.5)),
        ]),
        actions: [
          if (wide) Padding(padding: const EdgeInsets.only(right: 20), child: FilledButton.icon(
            onPressed: newReport, icon: const Icon(Icons.add), label: const Text('Signaler un problème')))
          else IconButton.filledTonal(onPressed: newReport, tooltip: 'Nouveau signalement', icon: const Icon(Icons.add)),
          if (!wide) const SizedBox(width: 12),
        ],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Color(0xFFE5EAF3))),
      ),
      body: wide ? Row(children: [
        Container(
          width: 260, color: Colors.white,
          child: Column(children: [
            const SizedBox(height: 24),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 19), child: Row(children: [
              Container(width: 7, height: 7, decoration: const BoxDecoration(color: accent, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Text('ESPACE SIGNALEMENT', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF8995AA), fontSize: 11, letterSpacing: 1)),
            ])),
            const SizedBox(height: 18),
            Expanded(child: NavigationRail(
              backgroundColor: Colors.white,
              extended: true,
              minExtendedWidth: 250,
              selectedIndex: page,
              onDestinationSelected: select,
              useIndicator: true,
              indicatorColor: const Color(0xFFE5EEFF),
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded, color: primary), label: Text('Dashboard')),
                NavigationRailDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle, color: primary), label: Text('Nouveau signalement')),
                NavigationRailDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt, color: primary), label: Text('Gestion des signalements')),
                NavigationRailDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map, color: primary), label: Text('Carte GPS')),
              ],
            )),
            const Spacer(),
            const Padding(padding: EdgeInsets.all(16), child: Text('ROAD ALERT • Mode local', style: TextStyle(fontSize: 11, color: Color(0xFF98A4B8)))),
          ]),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE5EAF3)),
        Expanded(child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation,
            child: SlideTransition(position: Tween<Offset>(begin: const Offset(0.025, 0), end: Offset.zero).animate(animation), child: child)),
          child: KeyedSubtree(key: ValueKey('$page-$formId'), child: current),
        )),
      ]) : AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: KeyedSubtree(key: ValueKey('$page-$formId'), child: current),
      ),
      bottomNavigationBar: wide ? null : NavigationBar(
        height: 75,
        selectedIndex: page,
        onDestinationSelected: select,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard, color: primary), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle, color: primary), label: 'Nouveau'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt, color: primary), label: 'Gestion'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map, color: primary), label: 'Carte'),
        ],
      ),
    );
  }

}

class ReportForm extends StatefulWidget {
  final Map<String, dynamic>? original;
  final Future<void> Function(Map<String, dynamic>) onSave;
  const ReportForm({super.key, required this.original, required this.onSave});
  @override
  State<ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<ReportForm> {
  final keyForm = GlobalKey<FormState>();
  late final TextEditingController title, description, address, lat, lon;
  String kind = kinds.first, level = 'Moyenne', status = 'Nouveau';
  String imageBase64 = '';
  bool locating = false, saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.original;
    title = TextEditingController(text: '${r?['titre'] ?? ''}');
    description = TextEditingController(text: '${r?['description'] ?? ''}');
    address = TextEditingController(text: '${r?['lieu'] ?? ''}');
    lat = TextEditingController(text: '${r?['lat'] ?? ''}');
    lon = TextEditingController(text: '${r?['lon'] ?? ''}');
    kind = '${r?['type'] ?? kinds.first}';
    level = '${r?['gravite'] ?? 'Moyenne'}';
    status = '${r?['statut'] ?? 'Nouveau'}';
    imageBase64 = '${r?['photo'] ?? ''}';
  }

  @override
  void dispose() {
    title.dispose(); description.dispose(); address.dispose(); lat.dispose(); lon.dispose();
    super.dispose();
  }

  Future<void> getGps() async {
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw Exception('Activez la localisation de votre appareil.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Autorisation de localisation refusée.');
      }
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      lat.text = p.latitude.toStringAsFixed(6);
      lon.text = p.longitude.toStringAsFixed(6);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GPS : $e')));
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> pickImage() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 650, imageQuality: 30);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > 400000) throw Exception('Image trop volumineuse.');
      if (mounted) setState(() => imageBase64 = base64Encode(bytes));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo : $e')));
    }
  }

  Widget dropdown(String label, String value, List<String> values, ValueChanged<String> onChanged) => DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'), initialValue: value, decoration: InputDecoration(labelText: label),
        items: values.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) { if (v != null) setState(() => onChanged(v)); },
      );

  Future<void> submit() async {
    if (saving || !(keyForm.currentState?.validate() ?? false)) return;
    setState(() => saving = true);
    try {
      await widget.onSave({
        'titre': title.text.trim(), 'description': description.text.trim(),
        'lieu': address.text.trim(), 'lat': lat.text.trim(), 'lon': lon.text.trim(),
        'type': kind, 'gravite': level, 'statut': status, 'photo': imageBase64,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760),
          child: Card(color: Colors.white, child: Padding(padding: const EdgeInsets.all(24),
            child: Form(key: keyForm, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Row(children: [Icon(Icons.edit_location_alt_outlined, color: primary, size: 26), SizedBox(width: 10), Text('SIGNALEMENT ROUTIER', style: TextStyle(color: primary, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.1))]),
              const SizedBox(height: 11),
              Text(widget.original == null ? 'Nouveau signalement' : 'Modifier le signalement', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: ink)),
              const SizedBox(height: 5),
              const Text('Décrivez le problème pour faciliter son identification.', style: TextStyle(color: Color(0xFF66738B))),
              const SizedBox(height: 18),
              TextFormField(controller: title, decoration: const InputDecoration(labelText: 'Titre *'), validator: requiredText),
              const SizedBox(height: 12),
              dropdown('Type de dégradation', kind, kinds, (v) => kind = v),
              const SizedBox(height: 12),
              TextFormField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description *'), validator: requiredText),
              const SizedBox(height: 12),
              TextFormField(controller: address, decoration: const InputDecoration(labelText: 'Localisation / Adresse *'), validator: requiredText),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(width: 180, child: TextFormField(controller: lat, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Latitude'), validator: (v) => coordinate(v, -90, 90))),
                SizedBox(width: 180, child: TextFormField(controller: lon, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'Longitude'), validator: (v) => coordinate(v, -180, 180))),
                OutlinedButton.icon(onPressed: locating ? null : getGps, icon: const Icon(Icons.my_location), label: Text(locating ? 'Localisation...' : 'Utiliser mon GPS')),
              ]),
              const SizedBox(height: 12),
              dropdown('Gravité', level, levels, (v) => level = v),
              const SizedBox(height: 12),
              dropdown('Statut', status, statuses, (v) => status = v),
              const SizedBox(height: 15),
              OutlinedButton.icon(onPressed: pickImage, icon: const Icon(Icons.photo), label: const Text('Choisir une photo')),
              if (imageBase64.isNotEmpty) ...[
                const SizedBox(height: 10),
                Image.memory(base64Decode(imageBase64), height: 160, fit: BoxFit.contain),
                TextButton.icon(onPressed: () => setState(() => imageBase64 = ''), icon: const Icon(Icons.delete), label: const Text('Retirer la photo')),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(onPressed: saving ? null : submit, icon: const Icon(Icons.save_outlined), label: Text(saving ? 'Enregistrement...' : 'Enregistrer le signalement')),
            ])),
          )),
        )),
      );

  String? requiredText(String? text) => text == null || text.trim().isEmpty ? 'Champ obligatoire' : null;
  String? coordinate(String? text, double min, double max) {
    if (text == null || text.trim().isEmpty) return null;
    final number = double.tryParse(text.trim().replaceAll(',', '.'));
    return number == null || number < min || number > max ? 'Coordonnée invalide' : null;
  }
}


class RoadPill extends StatelessWidget {
  const RoadPill({super.key, required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(50)),
    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
  );
}

class RoadEmpty extends StatelessWidget {
  const RoadEmpty({super.key, required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 20),
    child: Column(children: [
      Icon(icon, size: 45, color: const Color(0xFF96AACA)),
      const SizedBox(height: 10),
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
      const SizedBox(height: 5),
      Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF78869B))),
    ]),
  ));
}



