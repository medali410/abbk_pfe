import 'package:flutter/material.dart';
import '../../../models/communication_models.dart';
import '../../../services/communication_service.dart';

class DocumentListWidget extends StatefulWidget {
  final String currentUserId;
  final CommunicationService communicationService;

  const DocumentListWidget({
    required this.currentUserId,
    required this.communicationService,
  });

  @override
  State<DocumentListWidget> createState() => _DocumentListWidgetState();
}

class _DocumentListWidgetState extends State<DocumentListWidget> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Upload button
        Container(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: _showUploadDialog,
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Télécharger un document'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
            ),
          ),
        ),
        // Documents list
        Expanded(
          child: StreamBuilder<List<Document>>(
            stream: communicationService.getSharedDocuments(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'Aucun document disponible',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final documents = snapshot.data!;
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: documents.length,
                itemBuilder: (context, index) {
                  final doc = documents[index];
                  return _buildDocumentTile(doc);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentTile(Document document) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: _getFileIcon(document.fileType),
        title: Text(document.fileName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Téléchargé par: ${document.uploadedBy}'),
            Text(
              'Taille: ${_formatFileSize(document.fileSizeBytes)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (BuildContext context) => [
            PopupMenuItem(
              child: const Text('Télécharger'),
              onTap: () => _downloadDocument(document),
            ),
            if (document.uploadedBy == widget.currentUserId)
              PopupMenuItem(
                child: const Text('Supprimer',
                    style: TextStyle(color: Colors.red)),
                onTap: () => _deleteDocument(document),
              ),
          ],
        ),
      ),
    );
  }

  Widget _getFileIcon(String fileType) {
    IconData icon = Icons.insert_drive_file;
    Color color = Colors.grey;

    if (fileType.contains('pdf')) {
      icon = Icons.picture_as_pdf;
      color = Colors.red;
    } else if (fileType.contains('word') || fileType.contains('document')) {
      icon = Icons.description;
      color = Colors.blue;
    } else if (fileType.contains('sheet') || fileType.contains('excel')) {
      icon = Icons.table_chart;
      color = Colors.green;
    } else if (fileType.contains('presentation')) {
      icon = Icons.slideshow;
      color = Colors.orange;
    } else if (fileType.contains('image')) {
      icon = Icons.image;
      color = Colors.purple;
    }

    return Icon(icon, color: color, size: 32);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }

  void _showUploadDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Télécharger un document'),
        content: Text(
          'Sélectionnez un fichier à télécharger',
          style: TextStyle(color: Colors.grey[600]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sélection de fichier...')),
              );
            },
            child: const Text('Parcourir'),
          ),
        ],
      ),
    );
  }

  void _downloadDocument(Document document) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Téléchargement de ${document.fileName}...')),
    );
  }

  void _deleteDocument(Document document) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmer la suppression'),
        content: Text('Êtes-vous sûr de vouloir supprimer ${document.fileName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              widget.communicationService.deleteDocument(
                document.id,
                widget.currentUserId,
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Document supprimé avec succès')),
              );
            },
            child: const Text('Supprimer',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
