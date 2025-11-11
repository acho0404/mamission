import 'package:flutter/material.dart';
import 'package:mamission/core/constants.dart'; // Import

class PhotoGridSection extends StatelessWidget {
  final List<String> photoUrls;
  final Function(String) onPhotoTap;

  const PhotoGridSection({
    super.key,
    required this.photoUrls,
    required this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) {
      return const SizedBox.shrink(); // Ne rien afficher si pas de photos
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
      child: Wrap(
        spacing: 12.0, // Espace horizontal
        runSpacing: 12.0, // Espace vertical
        children:
        photoUrls.map((url) => _buildPhotoItem(context, url)).toList(),
      ),
    );
  }

  Widget _buildPhotoItem(BuildContext context, String url) {
    // Calcule la taille pour 3 photos par ligne
    final double itemSize =
        (MediaQuery.of(context).size.width - 40 - 24) / 3;

    return GestureDetector(
      onTap: () => onPhotoTap(url), // Action de clic
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          width: itemSize,
          height: itemSize,
          color: Colors.grey[200], // Fond en attendant le chargement
          child: Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                      : null,
                  strokeWidth: 2,
                  color: kPrimary,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image, color: Colors.grey, size: 30),
          ),
        ),
      ),
    );
  }
}