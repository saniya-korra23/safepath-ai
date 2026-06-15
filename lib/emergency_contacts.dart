import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class EmergencyContacts extends StatefulWidget {
  const EmergencyContacts({super.key});

  @override
  State<EmergencyContacts> createState() => _EmergencyContactsState();
}

class _EmergencyContactsState extends State<EmergencyContacts> {
  final List<Map<String, String>> contacts = [
    {"name": "Mom", "number": "9154231004"},
    {"name": "Dad", "number": "9951897405"},
    {"name": "Brother", "number": "8328298266"},
  ];

  void callNumber(String number) async {
    final Uri url = Uri(
      scheme: 'tel',
      path: number,
    );

    await launchUrl(url);
  }

  void whatsappNumber(String number) async {
    final msg = "🚨 Emergency from SafePath AI";

    final url = Uri.parse(
      "https://wa.me/$number?text=${Uri.encodeComponent(msg)}",
    );

    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Emergency Contacts"),
        backgroundColor: Colors.red,
      ),
      body: ListView.builder(
        itemCount: contacts.length,
        itemBuilder: (context, index) {
          final contact = contacts[index];

          return Card(
            child: ListTile(
              title: Text(contact["name"]!),
              subtitle: Text(contact["number"]!),
              leading: const Icon(Icons.person),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.call, color: Colors.green),
                    onPressed: () =>
                        callNumber(contact["number"]!),
                  ),
                  IconButton(
                    icon: const Icon(Icons.message, color: Colors.blue),
                    onPressed: () =>
                        whatsappNumber(contact["number"]!),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}