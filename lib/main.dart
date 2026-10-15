import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const RoadAlertApp());

const primary = Color(0xFF155DB8);
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
          colorScheme: ColorScheme.fromSeed(seedColor: primary),
          scaffoldBackgroundColor: const Color(0xFFF3F6FC),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
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

  Widget reportCard(Map<String, dynamic> record) => Card(
        color: Colors.white,
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.report_problem_outlined)),
          title: Text('${record['titre']}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${record['lieu']} • ${record['type']}\n${record['statut']} — ${record['gravite']}'),
          isThreeLine: true,
          onTap: () => details(record),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'Voir') details(record);
              if (v == 'Modifier') editReport(record);
              if (v == 'Carte') onMap(record);
              if (v == 'Supprimer') remove(record);
            },
            itemBuilder: (context) => ['Voir', 'Modifier', 'Carte', 'Supprimer']
                .map((v) => PopupMenuItem(value: v, child: Text(v))).toList(),
          ),
        ),
      );

  Widget stat(String name, int number, IconData icon, Color color) => Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 28, color: color),
            const Spacer(),
            Text('$number', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );

  Widget dashboard() => ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Tableau de bord', style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
        const Text('Situation des dégradations routières'),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (c, box) => GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: box.maxWidth >= 800 ? 4 : 2,
              childAspectRatio: box.maxWidth >= 800 ? 1.65 : 1.3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: [
                stat('Total', reports.length, Icons.list, primary),
                stat('Nouveaux', reports.where((r) => r['statut'] == 'Nouveau').length, Icons.fiber_new, Colors.orange),
                stat('En cours', reports.where((r) => r['statut'] == 'En cours').length, Icons.schedule, Colors.purple),
                stat('Résolus', reports.where((r) => r['statut'] == 'Résolu').length, Icons.verified, Colors.green),
              ],
            )),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: newReport, icon: const Icon(Icons.add), label: const Text('Nouveau signalement')),
        const SizedBox(height: 24),
        const Text('Signalements récents', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        if (reports.isEmpty) const Card(child: ListTile(title: Text('Aucun signalement'), subtitle: Text('Ajoutez votre premier signalement.'))),
        ...reports.take(5).map(reportCard),
      ]);

  Widget listing() {
    final results = reports.where((r) {
      final content = '${r['titre']} ${r['lieu']} ${r['type']}'.toLowerCase();
      return content.contains(search.toLowerCase()) && (filter == 'Tous' || r['statut'] == filter);
    }).toList();
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Gestion des signalements', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
      const SizedBox(height: 14),
      TextField(decoration: const InputDecoration(labelText: 'Rechercher', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => search = v)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: filter,
        decoration: const InputDecoration(labelText: 'Statut'),
        items: ['Tous', ...statuses].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: (v) => setState(() => filter = v ?? 'Tous'),
      ),
      const SizedBox(height: 10),
      Text('${results.length} résultat(s)'),
      if (results.isEmpty) const Card(child: ListTile(title: Text('Aucun résultat'))),
      ...results.map(reportCard),
    ]);
  }

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
      Padding(padding: const EdgeInsets.all(12), child: Text('Carte GPS — ${markers.length} signalement(s) localisé(s)', style: const TextStyle(fontWeight: FontWeight.bold))),
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
      appBar: AppBar(backgroundColor: primary, foregroundColor: Colors.white, title: const Text('ROAD ALERT'),
          actions: [IconButton(onPressed: newReport, tooltip: 'Ajouter', icon: const Icon(Icons.add_circle_outline))]),
      body: wide ? Row(children: [
        NavigationRail(
          extended: true, selectedIndex: page, onDestinationSelected: select,
          destinations: const [
            NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), label: Text('Dashboard')),
            NavigationRailDestination(icon: Icon(Icons.add_circle_outline), label: Text('Nouveau signalement')),
            NavigationRailDestination(icon: Icon(Icons.list_alt), label: Text('Gestion des signalements')),
            NavigationRailDestination(icon: Icon(Icons.map_outlined), label: Text('Carte GPS')),
          ],
        ),
        const VerticalDivider(width: 1), Expanded(child: current),
      ]) : current,
      bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: page, onDestinationSelected: select, destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard), label: 'Accueil'),
        NavigationDestination(icon: Icon(Icons.add_circle), label: 'Nouveau'),
        NavigationDestination(icon: Icon(Icons.list_alt), label: 'Gestion'),
        NavigationDestination(icon: Icon(Icons.map), label: 'Carte'),
      ]),
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
        initialValue: value, decoration: InputDecoration(labelText: label),
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
          child: Card(color: Colors.white, child: Padding(padding: const EdgeInsets.all(20),
            child: Form(key: keyForm, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.original == null ? 'Nouveau signalement' : 'Modifier le signalement', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
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
              FilledButton.icon(onPressed: saving ? null : submit, icon: const Icon(Icons.save), label: Text(saving ? 'Enregistrement...' : 'Enregistrer le signalement')),
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
