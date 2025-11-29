import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:mamission/shared/apple_appbar.dart';

// -----------------------------------------------------------------------------
// THEME & CONSTANTES (Même ADN que MissionCreatePage)
// -----------------------------------------------------------------------------
class AppTheme {
  static const Color bgLight = Color(0xFFF3F6FF);
  static const Color neonPrimary = Color(0xFF6C63FF);
  static const Color neonCyan = Color(0xFF00B8D4);
  static const Color textDark = Color(0xFF1A1F36);
  static const Color textGrey = Color(0xFF6E7787);

  static BoxDecoration glassBox({double radius = 24, bool isSelected = false}) {
    return BoxDecoration(
      color: isSelected ? Colors.white : Colors.white.withOpacity(0.65),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: isSelected ? neonPrimary : Colors.white,
        width: isSelected ? 1.5 : 1,
      ),
      boxShadow: [
        BoxShadow(
          color:
          isSelected ? neonPrimary.withOpacity(0.25) : Colors.black.withOpacity(0.03),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// PAGE PRINCIPALE : RECHERCHE PRESTATAIRE
// -----------------------------------------------------------------------------
class AllProvidersPage extends StatefulWidget {
  const AllProvidersPage({super.key});

  @override
  State<AllProvidersPage> createState() => _AllProvidersPageState();
}

class _AllProvidersPageState extends State<AllProvidersPage> {
  // --- ÉTAT DES FILTRES ---
  String _searchQuery = "";
  String _selectedCategory = "Tous";
  RangeValues _priceRange = const RangeValues(0, 300); // Prix min/max
  bool _onlyVerified = false;
  double _minRating = 0.0;
  String _sortBy = "Pertinence"; // Pertinence, Prix croiss., Notes
  String _selectedZone = "Partout"; // Partout, ≤ 5 km, ≤ 10 km, ≤ 20 km


  // --- DONNÉES MOCK (Simule Firebase) ---
  final List<String> _categories = [
    "Tous",
    "⚡ Élec",
    "🔧 Plomberie",
    "🧹 Ménage",
    "💻 Dev",
    "🔨 Bricolage",
    "🎨 Design",
  ];

  final List<Map<String, dynamic>> _allProviders = [
    {
      "id": "1",
      "name": "Achraf M.",
      "job": "Ingénieur Fullstack",
      "location": "Grenoble",
      "distance": "2.5 km",
      "rating": 4.9,
      "reviews": 124,
      "jobs_done": 45,
      "img": "https://i.pravatar.cc/300?img=11",
      "price": 35,
      "verified": true,
      "cat": "💻 Dev"
    },
    {
      "id": "2",
      "name": "Sarah L.",
      "job": "Architecte d'intérieur",
      "location": "Lyon",
      "distance": "15 km",
      "rating": 4.8,
      "reviews": 89,
      "jobs_done": 32,
      "img": "https://i.pravatar.cc/300?img=5",
      "price": 60,
      "verified": true,
      "cat": "🎨 Design"
    },
    {
      "id": "3",
      "name": "Jean-Pierre",
      "job": "Plombier Artisan",
      "location": "Paris 12",
      "distance": "0.8 km",
      "rating": 4.5,
      "reviews": 210,
      "jobs_done": 560,
      "img": "https://i.pravatar.cc/300?img=3",
      "price": 50,
      "verified": true,
      "cat": "🔧 Plomberie"
    },
    {
      "id": "4",
      "name": "Moussa D.",
      "job": "Électricien Bâtiment",
      "location": "Marseille",
      "distance": "5 km",
      "rating": 5.0,
      "reviews": 42,
      "jobs_done": 88,
      "img": "https://i.pravatar.cc/300?img=8",
      "price": 45,
      "verified": false,
      "cat": "⚡ Élec"
    },
    {
      "id": "5",
      "name": "Sophie K.",
      "job": "Femme de ménage",
      "location": "Grenoble",
      "distance": "1.2 km",
      "rating": 4.7,
      "reviews": 15,
      "jobs_done": 20,
      "img": "https://i.pravatar.cc/300?img=9",
      "price": 25,
      "verified": true,
      "cat": "🧹 Ménage"
    },
    {
      "id": "6",
      "name": "Lucas V.",
      "job": "Menuisier",
      "location": "Echirolles",
      "distance": "6 km",
      "rating": 4.2,
      "reviews": 8,
      "jobs_done": 5,
      "img": "https://i.pravatar.cc/300?img=12",
      "price": 40,
      "verified": false,
      "cat": "🔨 Bricolage"
    },
  ];

  // --- LOGIQUE MÉTIER DE FILTRAGE ---
  // --- LOGIQUE MÉTIER DE FILTRAGE ---
  List<Map<String, dynamic>> get _filteredList {
    List<Map<String, dynamic>> list = _allProviders.where((p) {
      // 1. Filtre Catégorie
      bool matchCat = _selectedCategory == "Tous" || p['cat'] == _selectedCategory;

      // 2. Filtre Texte
      bool matchSearch = p['name'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p['job'].toLowerCase().contains(_searchQuery.toLowerCase());

      // 3. Filtre Prix
      bool matchPrice =
          p['price'] >= _priceRange.start && p['price'] <= _priceRange.end;

      // 4. Filtre Vérifié
      bool matchVerified = !_onlyVerified || p['verified'] == true;

      // 5. Filtre Note
      bool matchRating = p['rating'] >= _minRating;

      // 6. Filtre Zone (basé sur le champ "distance": "2.5 km")
      bool matchZone = true;
      if (_selectedZone != "Partout") {
        final distStr = (p['distance'] as String?) ?? "";
        final parts = distStr.split(" ");
        final km = double.tryParse(parts.isNotEmpty ? parts.first : "") ?? 9999;

        if (_selectedZone == "≤ 5 km") {
          matchZone = km <= 5;
        } else if (_selectedZone == "≤ 10 km") {
          matchZone = km <= 10;
        } else if (_selectedZone == "≤ 20 km") {
          matchZone = km <= 20;
        }
      }

      return matchCat && matchSearch && matchPrice && matchVerified && matchRating && matchZone;
    }).toList();

    // 7. Tri
    if (_sortBy == "Prix croissant") {
      list.sort((a, b) => (a['price'] as int).compareTo(b['price'] as int));
    } else if (_sortBy == "Meilleures notes") {
      list.sort((a, b) => (b['rating'] as double).compareTo(a['rating'] as double));
    }
    // "Pertinence" = ordre de base

    return list;
  }


  // --- UI: BOTTOM SHEET FILTRES ---
  // --- UI: BOTTOM SHEET FILTRES ---
// 👉 même esprit que "Tous les filtres" de la page Missions,
// mais adapté à la vitrine prestataires : tarif / vérifiés / note minimale / tri.
  // --- UI: BOTTOM SHEET FILTRES ---
// 👉 Tous les filtres vitrine prestataires : Zone, Catégories, Tarif, Garanties, Tri
  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            // options de zone utilisées dans le filtre
            final List<String> zoneOptions = [
              "Partout",
              "≤ 5 km",
              "≤ 10 km",
              "≤ 20 km",
            ];

            return StatefulBuilder(
              builder: (context, setSheetState) {
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.94),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.neonPrimary.withOpacity(0.25),
                            blurRadius: 40,
                            offset: const Offset(0, -12),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          // petit handle drag
                          Container(
                            width: 42,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "TOUS LES FILTRES",
                            style: TextStyle(
                              color: AppTheme.textDark,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // CONTENU SCROLLABLE
                          Expanded(
                            child: ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              children: [
                                // 1. ZONE
                                const _FilterSectionTitle("Zone"),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: zoneOptions.map((z) {
                                    final sel = _selectedZone == z;
                                    return ChoiceChip(
                                      label: Text(z),
                                      selected: sel,
                                      onSelected: (_) =>
                                          setSheetState(() => _selectedZone = z),
                                      selectedColor:
                                      AppTheme.neonPrimary.withOpacity(0.15),
                                      backgroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        side: BorderSide(
                                          color: sel
                                              ? AppTheme.neonPrimary
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                      labelStyle: TextStyle(
                                        color: sel
                                            ? AppTheme.neonPrimary
                                            : AppTheme.textDark,
                                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                    );
                                  }).toList(),
                                ),

                                const SizedBox(height: 24),

                                // 2. CATÉGORIES
                                const _FilterSectionTitle("Catégories"),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _categories.map((cat) {
                                    final sel = _selectedCategory == cat;
                                    return ChoiceChip(
                                      label: Text(cat),
                                      selected: sel,
                                      onSelected: (_) =>
                                          setSheetState(() => _selectedCategory = cat),
                                      selectedColor: AppTheme.neonPrimary,
                                      backgroundColor: Colors.white,
                                      labelStyle: TextStyle(
                                        color: sel ? Colors.white : AppTheme.textDark,
                                        fontWeight:
                                        sel ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    );
                                  }).toList(),
                                ),

                                const SizedBox(height: 24),

                                // 3. TRI
                                const _FilterSectionTitle("Trier par"),
                                Wrap(
                                  spacing: 10,
                                  children: ["Pertinence", "Prix croissant", "Meilleures notes"]
                                      .map((sort) {
                                    final isSel = _sortBy == sort;
                                    return ChoiceChip(
                                      label: Text(sort),
                                      selected: isSel,
                                      onSelected: (_) =>
                                          setSheetState(() => _sortBy = sort),
                                      selectedColor: AppTheme.neonPrimary,
                                      labelStyle: TextStyle(
                                        color: isSel ? Colors.white : AppTheme.textDark,
                                        fontWeight:
                                        isSel ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                      backgroundColor: Colors.grey[100],
                                      side: BorderSide.none,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    );
                                  }).toList(),
                                ),

                                const SizedBox(height: 24),

                                // 4. TARIF HORAIRE
                                const _FilterSectionTitle("Tarif horaire"),
                                RangeSlider(
                                  values: _priceRange,
                                  min: 0,
                                  max: 200,
                                  divisions: 20,
                                  activeColor: AppTheme.neonPrimary,
                                  inactiveColor: AppTheme.neonPrimary.withOpacity(0.2),
                                  labels: RangeLabels(
                                    "${_priceRange.start.round()} €/h",
                                    "${_priceRange.end.round()} €/h",
                                  ),
                                  onChanged: (v) =>
                                      setSheetState(() => _priceRange = v),
                                ),
                                Center(
                                  child: Text(
                                    "${_priceRange.start.round()}€ /h - ${_priceRange.end.round()}€ /h",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.neonPrimary,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // 5. GARANTIES
                                const _FilterSectionTitle("Garanties"),
                                SwitchListTile.adaptive(
                                  title: const Text(
                                    "Profils vérifiés uniquement",
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  value: _onlyVerified,
                                  activeColor: AppTheme.neonPrimary,
                                  contentPadding: EdgeInsets.zero,
                                  onChanged: (v) =>
                                      setSheetState(() => _onlyVerified = v),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Note minimum : ${_minRating > 0 ? _minRating.toStringAsFixed(1) : "Toutes"}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                                Slider(
                                  value: _minRating,
                                  min: 0,
                                  max: 5,
                                  divisions: 5,
                                  activeColor: Colors.amber,
                                  label: _minRating.toStringAsFixed(1),
                                  onChanged: (v) =>
                                      setSheetState(() => _minRating = v),
                                ),

                                const SizedBox(height: 10),
                              ],
                            ),
                          ),

                          // BOUTONS BAS
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                            child: Row(
                              children: [
                                TextButton(
                                  onPressed: () {
                                    setSheetState(() {
                                      _sortBy = "Pertinence";
                                      _priceRange = const RangeValues(20, 150);
                                      _onlyVerified = false;
                                      _minRating = 0.0;
                                      _selectedZone = "Partout";
                                      _selectedCategory = "Tous";
                                    });
                                  },
                                  child: const Text(
                                    "Réinitialiser",
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const Spacer(),
                                SizedBox(
                                  width: 170,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      // on applique sur la page principale
                                      setState(() {});
                                      Navigator.pop(context);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.textDark,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: const Text(
                                      "Appliquer",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }



  // --- TOGGLE Missions / Prestataires — même style que MissionListPage ---
  Widget _buildTopToggleRow(BuildContext context) {
    return Container(
      height: 52,
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(
          color: Colors.white.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Row(
            children: [
              _buildToggleChip(
                label: 'Missions',
                selected: false, // 👉 on est sur PRESTATAIRES ici
                onTap: () {
                  Navigator.pop(context); // retour à Explore (Missions)
                },
              ),
              _buildToggleChip(
                label: 'Prestataires',
                selected: true,
                onTap: () {
                  // déjà sur cette page
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            gradient: selected
                ? const LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
                : null,
            color: selected ? null : Colors.transparent,
            boxShadow: selected
                ? [
              BoxShadow(
                color: const Color(0xFF6C63FF).withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ]
                : [],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                fontFamily: 'Plus Jakarta Sans',
                color: selected ? Colors.white : AppTheme.neonPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final displayList = _filteredList;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppTheme.bgLight,
        appBar: buildAppleMissionAppBar(
          title: "Explorer",
        ),
        body: Stack(
          children: [
            // --- FOND ORBES FUTURISTES ---
            Positioned(top: -100, right: -100, child: _buildBlurOrb(AppTheme.neonPrimary)),
            Positioned(top: 300, left: -50, child: _buildBlurOrb(AppTheme.neonCyan)),

            // --- CONTENU PRINCIPAL ---
            SafeArea(
              top: false, // on a déjà l'appBar
              child: Column(
                children: [
                  // 1. TOGGLE Missions / Prestataires
                  _buildTopToggleRow(context),

                  // 2. SEARCH & FILTER
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: AppTheme.glassBox(),
                            child: TextField(
                              onChanged: (v) => setState(() => _searchQuery = v),
                              style: const TextStyle(color: AppTheme.textDark),
                              decoration: InputDecoration(
                                hintText: "Rechercher un expert (ex: Plombier...)",
                                hintStyle:
                                TextStyle(color: AppTheme.textGrey.withOpacity(0.6)),
                                prefixIcon:
                                const Icon(Icons.search, color: AppTheme.neonPrimary),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 15,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: _openFilterSheet,
                          child: Container(
                            height: 50,
                            width: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(
                                color: Colors.grey.shade300,
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.tune_rounded,
                              color: AppTheme.textDark,
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. CATÉGORIES (Chips Horizontaux)
                  SizedBox(
                    height: 50,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _categories.length,
                      itemBuilder: (ctx, index) {
                        final cat = _categories[index];
                        final isSel = _selectedCategory == cat;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedCategory = cat),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 10, top: 5, bottom: 5),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSel ? AppTheme.neonPrimary : Colors.white.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(30),
                              border: isSel ? null : Border.all(color: Colors.white),
                              boxShadow: isSel
                                  ? [
                                BoxShadow(
                                  color: AppTheme.neonPrimary.withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ]
                                  : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 4,
                                )
                              ],
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                color: isSel ? Colors.white : AppTheme.textGrey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 10),

                  // 4. LISTE DES PRESTATAIRES (GRID)
                  Expanded(
                    child: displayList.isEmpty
                        ? _buildEmptyState()
                        : AnimationLimiter(
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.70,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: displayList.length,
                        itemBuilder: (ctx, index) {
                          return AnimationConfiguration.staggeredGrid(
                            position: index,
                            duration: const Duration(milliseconds: 500),
                            columnCount: 2,
                            child: ScaleAnimation(
                              child: FadeInAnimation(
                                child: _NeonProviderCard(data: displayList[index]),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS HELPER ---
  Widget _buildBlurOrb(Color color) {
    return Container(
      width: 300,
      height: 300,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.15),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
        child: Container(color: Colors.transparent),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 60,
            color: AppTheme.textGrey.withOpacity(0.3),
          ),
          const SizedBox(height: 10),
          Text(
            "Aucun expert trouvé",
            style: TextStyle(
              color: AppTheme.textGrey.withOpacity(0.5),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// WIDGET CARTE PRESTATAIRE "NEON PRO"
// -----------------------------------------------------------------------------
class _NeonProviderCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _NeonProviderCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.glassBox(radius: 20, isSelected: false).copyWith(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.8),
            Colors.white.withOpacity(0.4),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. IMAGE + BADGE
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      image: DecorationImage(
                        image: CachedNetworkImageProvider(data['img']),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  if (data['verified'])
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.verified,
                          color: AppTheme.neonPrimary,
                          size: 14,
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Colors.amber,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "${data['rating']}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 2. INFOS
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['name'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data['job'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textGrey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 10,
                            color: AppTheme.textGrey.withOpacity(0.6),
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              "${data['location']} (${data['distance']})",
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.textGrey.withOpacity(0.8),
                              ),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),

                  // 3. PRIX & ACTION
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${data['price']}€/h",
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppTheme.neonPrimary,
                        ),
                      ),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.neonPrimary, AppTheme.neonCyan],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.neonPrimary.withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            )
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      )
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _FilterSectionTitle extends StatelessWidget {
  final String title;
  const _FilterSectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppTheme.textGrey,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
