import 'package:flutter/material.dart';
import 'widgets/message_equipe_view.dart';

class MessageEquipePage extends StatelessWidget {
  const MessageEquipePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Legacy support for arguments via ModalRoute
    final args = (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?) ?? {};
    
    return MessageEquipeView(
      technicianId: (args['technicianId'] ?? args['id'] ?? '').toString(),
      clientId: (args['clientId'] ?? args['companyId'] ?? '').toString(),
      senderName: (args['name'] ?? 'Technicien').toString(),
      senderRole: (args['role'] ?? 'technician').toString().toLowerCase(),
      embedded: false,
    );
  }
}
