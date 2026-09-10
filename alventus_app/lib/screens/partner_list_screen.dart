import 'package:flutter/material.dart';
import '../services/odoo_service.dart';
import '../models/partner.dart';

class PartnerListScreen extends StatefulWidget {
  const PartnerListScreen({super.key});

  @override
  State<PartnerListScreen> createState() => _PartnerListScreenState();
}

class _PartnerListScreenState extends State<PartnerListScreen> {
  final OdooService _odooService = OdooService();
  List<Partner> _partners = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPartners();
  }

  Future<void> _loadPartners() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _odooService.fetchPartners();

    if (!mounted) return;

    if (result['success'] == true) {
      final List<dynamic> records = result['result'] as List<dynamic>;
      setState(() {
        _partners = records
            .map((json) => Partner.fromJson(json as Map<String, dynamic>))
            .toList();
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = result['error'] as String?;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contactos'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadPartners,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_partners.isEmpty) {
      return const Center(
        child: Text('No hay contactos disponibles'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPartners,
      child: ListView.builder(
        itemCount: _partners.length,
        itemBuilder: (context, index) {
          final partner = _partners[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue,
                child: Text(
                  partner.name.isNotEmpty ? partner.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(partner.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (partner.email != null && partner.email!.isNotEmpty)
                    Text(partner.email!),
                  if (partner.phone != null && partner.phone!.isNotEmpty)
                    Text(partner.phone!),
                  if (partner.city != null && partner.city!.isNotEmpty)
                    Text(partner.city!),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          );
        },
      ),
    );
  }
}