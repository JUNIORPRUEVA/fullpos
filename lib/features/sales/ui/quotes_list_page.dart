import 'package:flutter/material.dart';

/// Página de lista de cotizaciones
class QuotesListPage extends StatelessWidget {
  const QuotesListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cotizaciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {},
            tooltip: 'Filtros',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
            tooltip: 'Buscar',
          ),
        ],
      ),
      body: const Center(
        child: Text('Lista de cotizaciones'),
      ),
    );
  }
}
