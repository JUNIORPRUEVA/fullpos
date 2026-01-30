import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';

enum TrainingSessionType { installation, manual, modules }

class TrainingSection {
  final String title;
  final String? description;
  final List<String> bullets;

  const TrainingSection({
    required this.title,
    this.description,
    this.bullets = const [],
  });
}

class TrainingDoc {
  final String id;
  final TrainingSessionType session;
  final String title;
  final String summary;
  final List<String> keywords;
  final List<TrainingSection> sections;

  const TrainingDoc({
    required this.id,
    required this.session,
    required this.title,
    required this.summary,
    required this.keywords,
    required this.sections,
  });
}

class TrainingSearchResult {
  final TrainingDoc doc;
  final String preview;

  const TrainingSearchResult({required this.doc, required this.preview});
}

class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key});

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  final TextEditingController _searchController = TextEditingController();

  TrainingSessionType? _filterSession;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allDocs = _trainingDocs;

    final filteredDocs = allDocs.where((doc) {
      if (_filterSession != null && doc.session != _filterSession) return false;
      return true;
    }).toList();

    final q = _query.trim().toLowerCase();
    final hasQuery = q.isNotEmpty;

    final results = hasQuery
        ? _search(allDocs, q)
        : const <TrainingSearchResult>[];

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: const Text('Entrenamiento')),
      body: Padding(
        padding: const EdgeInsets.all(AppSizes.paddingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchBar(),
            const SizedBox(height: AppSizes.spaceM),
            _buildSessionFilters(),
            const SizedBox(height: AppSizes.spaceM),
            Expanded(
              child: hasQuery
                  ? _buildSearchResults(results)
                  : _buildDocList(filteredDocs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(color: AppColors.surfaceLightBorder),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _query = value;
          });
        },
        decoration: const InputDecoration(
          hintText:
              'Buscar en entrenamiento (ej: instalar, impresora, caja, reportes, usuarios...)',
          prefixIcon: Icon(Icons.search),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildSessionFilters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Todo'),
          selected: _filterSession == null,
          onSelected: (_) => setState(() => _filterSession = null),
        ),
        ChoiceChip(
          label: const Text('Instalación'),
          selected: _filterSession == TrainingSessionType.installation,
          onSelected: (_) =>
              setState(() => _filterSession = TrainingSessionType.installation),
        ),
        ChoiceChip(
          label: const Text('Manual y funciones'),
          selected: _filterSession == TrainingSessionType.manual,
          onSelected: (_) =>
              setState(() => _filterSession = TrainingSessionType.manual),
        ),
        ChoiceChip(
          label: const Text('Capacitación por módulo'),
          selected: _filterSession == TrainingSessionType.modules,
          onSelected: (_) =>
              setState(() => _filterSession = TrainingSessionType.modules),
        ),
      ],
    );
  }

  Widget _buildSearchResults(List<TrainingSearchResult> results) {
    if (results.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSizes.paddingM),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
          border: Border.all(color: AppColors.surfaceLightBorder),
        ),
        child: const Text(
          'No se encontraron coincidencias. Prueba con otra palabra (ej: NCF, impresora, backup, cierre de caja, descuentos, cotización).',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final r = results[index];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            border: Border.all(color: AppColors.surfaceLightBorder),
          ),
          child: ListTile(
            leading: Icon(
              _iconForSession(r.doc.session),
              color: AppColors.teal,
            ),
            title: Text(
              r.doc.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(r.preview),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openDoc(r.doc),
          ),
        );
      },
    );
  }

  Widget _buildDocList(List<TrainingDoc> docs) {
    if (docs.isEmpty) {
      return const Center(child: Text('No hay contenido para este filtro.'));
    }

    return ListView.separated(
      itemCount: docs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final doc = docs[index];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            border: Border.all(color: AppColors.surfaceLightBorder),
          ),
          child: ListTile(
            leading: Icon(_iconForSession(doc.session), color: AppColors.teal),
            title: Text(
              doc.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(doc.summary),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openDoc(doc),
          ),
        );
      },
    );
  }

  void _openDoc(TrainingDoc doc) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TrainingDocPage(doc: doc)),
    );
  }

  static IconData _iconForSession(TrainingSessionType session) {
    switch (session) {
      case TrainingSessionType.installation:
        return Icons.download_for_offline;
      case TrainingSessionType.manual:
        return Icons.menu_book;
      case TrainingSessionType.modules:
        return Icons.dashboard_customize;
    }
  }

  static List<TrainingSearchResult> _search(List<TrainingDoc> docs, String q) {
    String normalize(String s) => s.toLowerCase();

    final results = <TrainingSearchResult>[];

    for (final doc in docs) {
      final fullText = StringBuffer()
        ..writeln(doc.title)
        ..writeln(doc.summary)
        ..writeln(doc.keywords.join(' '));

      for (final s in doc.sections) {
        fullText.writeln(s.title);
        if (s.description != null) fullText.writeln(s.description);
        for (final b in s.bullets) {
          fullText.writeln(b);
        }
      }

      final haystack = normalize(fullText.toString());
      final idx = haystack.indexOf(q);
      if (idx < 0) continue;

      final raw = fullText.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      final rawLower = normalize(raw);
      final rawIdx = rawLower.indexOf(q);
      final start = (rawIdx - 45).clamp(0, raw.length);
      final end = (rawIdx + q.length + 55).clamp(0, raw.length);

      final preview =
          (start > 0 ? '…' : '') +
          raw.substring(start, end) +
          (end < raw.length ? '…' : '');

      results.add(TrainingSearchResult(doc: doc, preview: preview));
    }

    return results;
  }
}

class TrainingDocPage extends StatelessWidget {
  final TrainingDoc doc;

  const TrainingDocPage({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: Text(doc.title)),
      body: Padding(
        padding: const EdgeInsets.all(AppSizes.paddingL),
        child: ListView(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSizes.paddingM),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
                border: Border.all(color: AppColors.surfaceLightBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _sessionLabel(doc.session),
                    style: const TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(doc.summary, style: const TextStyle(height: 1.35)),
                ],
              ),
            ),
            const SizedBox(height: AppSizes.spaceL),
            ...doc.sections.map((s) => _SectionCard(section: s)),
            const SizedBox(height: AppSizes.spaceL),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSizes.paddingM),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
                border: Border.all(color: AppColors.surfaceLightBorder),
              ),
              child: const Text(
                'Tip: si no encuentras algo, regresa y usa el buscador (arriba).',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _sessionLabel(TrainingSessionType s) {
    switch (s) {
      case TrainingSessionType.installation:
        return 'SESIÓN: INSTALACIÓN';
      case TrainingSessionType.manual:
        return 'SESIÓN: MANUAL Y FUNCIONALIDADES';
      case TrainingSessionType.modules:
        return 'SESIÓN: CAPACITACIÓN POR MÓDULO';
    }
  }
}

class _SectionCard extends StatelessWidget {
  final TrainingSection section;

  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(color: AppColors.surfaceLightBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.paddingM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              section.title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            if (section.description != null) ...[
              const SizedBox(height: 8),
              Text(section.description!, style: const TextStyle(height: 1.35)),
            ],
            if (section.bullets.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...section.bullets.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(height: 1.4)),
                      Expanded(
                        child: Text(b, style: const TextStyle(height: 1.4)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const List<TrainingDoc> _trainingDocs = [
  TrainingDoc(
    id: 'install_paso_a_paso',
    session: TrainingSessionType.installation,
    title: 'Instalación paso a paso (PC Windows)',
    summary:
        'Guía completa para instalar FULLPOS, preparar impresoras, crear tu primer negocio y dejar el sistema listo para vender.',
    keywords: [
      'instalar',
      'windows',
      'requisitos',
      'drivers',
      'impresora',
      'pdf',
      'actualizar',
      'backup',
      'base de datos',
    ],
    sections: [
      TrainingSection(
        title: '1) Antes de instalar (requisitos)',
        description:
            'Recomendación: realiza estos pasos con un usuario administrador de Windows. Si tienes antivirus corporativo, pide permiso para permitir la carpeta del sistema.',
        bullets: [
          'PC con Windows (recomendado Windows 10/11).',
          'Espacio libre: mínimo 2 GB (recomendado 5 GB).',
          'Impresora configurada en Windows (si usarás ticket).',
          'Acceso a internet (opcional pero recomendado para soporte/actualizaciones).',
          'Si vas a trabajar en red: define en qué PC estará la información principal y cómo se compartirán respaldos.',
        ],
      ),
      TrainingSection(
        title: '2) Descargar / instalar el programa',
        bullets: [
          'Cierra otras aplicaciones antes de iniciar.',
          'Ejecuta el instalador como Administrador.',
          'Sigue el asistente: Aceptar → Siguiente → Instalar → Finalizar.',
          'Si Windows pregunta por permisos o firewall, permite la ejecución.',
          'Al terminar, abre FULLPOS desde el acceso directo del escritorio o menú Inicio.',
        ],
      ),
      TrainingSection(
        title: '3) Primer arranque: configuración mínima',
        bullets: [
          'Entra a CONFIGURACIÓN → NEGOCIO y registra: nombre comercial, RNC, dirección, teléfono y datos fiscales.',
          'Configura moneda y cualquier dato requerido por tu operación.',
          'Ve a CONFIGURACIÓN → USUARIOS y crea usuarios (cajero, supervisor, administrador) con permisos correctos.',
          'Si tu negocio usa caja: abre una sesión de caja cuando el sistema lo solicite.',
        ],
      ),
      TrainingSection(
        title: '4) Impresora de ticket (paso a paso)',
        description:
            'El sistema imprime por la impresora que Windows tenga instalada. Primero asegúrate de que Windows imprime una página de prueba.',
        bullets: [
          'Conecta la impresora (USB / red) y instala el driver oficial.',
          'En Windows: Configuración → Impresoras → selecciona tu impresora → Imprimir página de prueba.',
          'En FULLPOS: CONFIGURACIÓN → IMPRESORA (si aplica) y selecciona tamaño/formato del ticket.',
          'Haz una prueba: crea un ticket simple y presiona imprimir.',
          'Si el ticket sale cortado o muy ancho: ajusta tamaño/fuente y vuelve a probar.',
        ],
      ),
      TrainingSection(
        title: '5) Primeros datos: productos, clientes y ventas',
        bullets: [
          'Registra productos: nombre, código, costo, precio, ITBIS y stock.',
          'Crea clientes frecuentes si necesitas historial o crédito.',
          'Realiza una venta de prueba: agrega 1 producto, selecciona método de pago, finaliza e imprime.',
        ],
      ),
      TrainingSection(
        title: '6) Respaldo y recuperación (muy importante)',
        description:
            'Tu operación depende del respaldo. Define una rutina diaria/semanal según el volumen de ventas.',
        bullets: [
          'Entra a CONFIGURACIÓN → BACKUP.',
          'Activa respaldo manual o automático (según lo que esté disponible en tu versión).',
          'Guarda respaldos fuera de la PC (USB o nube).',
          'Para restaurar, hazlo solo con autorización (administrador) y preferiblemente fuera de horas de venta.',
        ],
      ),
      TrainingSection(
        title: '7) Qué hacer si algo falla (check rápido)',
        bullets: [
          'Si no imprime: prueba impresión en Windows; revisa cable/driver/cola de impresión.',
          'Si se cierra o queda lento: reinicia el programa; si persiste, reinicia la PC.',
          'Si necesitas ayuda técnica: ve a CONFIGURACIÓN → SOPORTE y genera el archivo para soporte.',
          'Busca el problema en Entrenamiento con el buscador (ej: “impresora”, “caja”, “NCF”).',
        ],
      ),
    ],
  ),
  TrainingDoc(
    id: 'manual_flujo_general',
    session: TrainingSessionType.manual,
    title: 'Manual general: cómo se trabaja en FULLPOS',
    summary:
        'Explica el flujo típico: iniciar, abrir caja, vender, imprimir, hacer cierres, consultar reportes y mantener la información segura.',
    keywords: [
      'manual',
      'flujo',
      'inicio',
      'caja',
      'ticket',
      'venta',
      'cierre',
      'reportes',
    ],
    sections: [
      TrainingSection(
        title: 'Inicio rápido (día a día)',
        bullets: [
          'Inicia sesión con tu usuario.',
          'Si aplica, abre caja (turno) y verifica el monto inicial.',
          'Verifica impresora y conexión si vas a imprimir.',
          'Crea/abre un ticket y comienza a facturar.',
        ],
      ),
      TrainingSection(
        title: 'Venta (pasos claros)',
        bullets: [
          'Busca productos por nombre/código/lector y agrégalos al ticket.',
          'Ajusta cantidad, precio o descuentos según permisos.',
          'Selecciona cliente si necesitas factura a nombre o crédito.',
          'Elige método de pago (efectivo, tarjeta, transferencia, mixto si aplica).',
          'Confirma: imprime ticket y guarda el comprobante si aplica.',
        ],
      ),
      TrainingSection(
        title: 'Anulación, devoluciones y cambios (buenas prácticas)',
        bullets: [
          'Evita borrar ventas; usa anulación/devolución si el sistema lo soporta, para mantener el historial.',
          'Si hay control de permisos, solicita autorización del supervisor.',
          'Documenta la razón (cliente, error de precio, producto dañado) para auditoría.',
        ],
      ),
      TrainingSection(
        title: 'Cierre de caja',
        bullets: [
          'Registra entradas/salidas durante el turno si corresponde.',
          'Al cerrar, cuenta efectivo y compara con el sistema.',
          'Si hay diferencia, valida: devoluciones, pagos mixtos, errores de cambio, tickets pendientes.',
          'Guarda reporte/corte como respaldo interno.',
        ],
      ),
      TrainingSection(
        title: 'Reportes básicos',
        bullets: [
          'Ventas del día y por rango de fechas.',
          'Productos más vendidos y márgenes (si está habilitado).',
          'Movimientos de caja y cortes.',
          'Historial por cliente (si usas clientes).',
        ],
      ),
      TrainingSection(
        title: 'Seguridad y control',
        bullets: [
          'Crea usuarios por rol: cajero, supervisor, admin.',
          'Activa permisos por módulo: editar precios, anular ventas, ver reportes, etc.',
          'Usa PIN/autorización para acciones sensibles si está habilitado.',
        ],
      ),
    ],
  ),
  TrainingDoc(
    id: 'funcionalidades_clave',
    session: TrainingSessionType.manual,
    title: 'Funcionalidades del programa (lista completa)',
    summary:
        'Resumen organizado de lo que puedes hacer: ventas, tickets, inventario, clientes, caja, reportes, usuarios, respaldo y configuración.',
    keywords: [
      'funcionalidades',
      'modulos',
      'ventas',
      'inventario',
      'clientes',
      'reportes',
      'usuarios',
      'backup',
      'impresora',
      'configuracion',
    ],
    sections: [
      TrainingSection(
        title: 'Ventas y tickets',
        bullets: [
          'Crear tickets, agregar productos, modificar cantidades y aplicar descuentos (según permisos).',
          'Seleccionar cliente, método de pago y finalizar ventas.',
          'Imprimir tickets y validar formato/ancho si aplica.',
        ],
      ),
      TrainingSection(
        title: 'Productos e inventario',
        bullets: [
          'Crear/editar productos con precio, costo, ITBIS, códigos y control de stock.',
          'Organizar por categorías y mantener inventario actualizado.',
        ],
      ),
      TrainingSection(
        title: 'Clientes',
        bullets: [
          'Registrar clientes con datos fiscales y contacto.',
          'Consultar historial de compras y comportamiento.',
        ],
      ),
      TrainingSection(
        title: 'Caja',
        bullets: [
          'Abrir/cerrar caja por turno y registrar movimientos.',
          'Ver totales por método de pago y controlar diferencias.',
        ],
      ),
      TrainingSection(
        title: 'Reportes',
        bullets: [
          'Reportes de ventas por día/rango, productos y caja.',
          'Exportar/consultar información según lo disponible.',
        ],
      ),
      TrainingSection(
        title: 'Usuarios y permisos',
        bullets: [
          'Administrar usuarios, roles y permisos por módulo.',
          'Proteger acciones sensibles con autorización cuando aplique.',
        ],
      ),
      TrainingSection(
        title: 'Configuración del negocio y sistema',
        bullets: [
          'Datos fiscales, contacto, monedas y parámetros del negocio.',
          'Impresora/ticket y ajustes de visual/tema si está disponible.',
        ],
      ),
      TrainingSection(
        title: 'Respaldo y soporte',
        bullets: [
          'Realizar backups y restauraciones con control.',
          'Generar logs para soporte desde CONFIGURACIÓN → SOPORTE.',
        ],
      ),
    ],
  ),
  TrainingDoc(
    id: 'capacitacion_modulos',
    session: TrainingSessionType.modules,
    title: 'Capacitación por módulo (ruta sugerida)',
    summary:
        'Ruta de aprendizaje: qué aprender primero y qué practicar en cada módulo para operar sin perderse.',
    keywords: ['capacitacion', 'modulos', 'practica', 'ruta', 'entrenamiento'],
    sections: [
      TrainingSection(
        title: 'Módulo 1: Ventas (lo esencial)',
        bullets: [
          'Objetivo: vender rápido sin errores.',
          'Práctica: crea 5 tickets con distintos productos; aplica un descuento; cambia cantidad; finaliza e imprime.',
          'Errores típicos: cobrar antes de seleccionar cliente, confundir precio/cantidad, imprimir sin probar impresora.',
        ],
      ),
      TrainingSection(
        title: 'Módulo 2: Caja (control y cierres)',
        bullets: [
          'Objetivo: que el efectivo cuadre con el sistema.',
          'Práctica: abre caja, registra una entrada/salida, vende con efectivo/tarjeta, cierra y revisa totales.',
          'Regla: todo movimiento debe quedar registrado.',
        ],
      ),
      TrainingSection(
        title: 'Módulo 3: Productos e inventario',
        bullets: [
          'Objetivo: catálogo limpio y precios correctos.',
          'Práctica: crea 10 productos, asigna códigos/categorías, revisa ITBIS y márgenes si aplica.',
          'Consejo: define una política de códigos (ej: por proveedor o por familia).',
        ],
      ),
      TrainingSection(
        title: 'Módulo 4: Clientes',
        bullets: [
          'Objetivo: ventas a nombre, historial y control de crédito.',
          'Práctica: crea 3 clientes, asigna datos fiscales, realiza una venta por cliente y consulta historial.',
        ],
      ),
      TrainingSection(
        title: 'Módulo 5: Reportes',
        bullets: [
          'Objetivo: tomar decisiones con datos.',
          'Práctica: revisa ventas del día, ventas por rango, productos top y cortes de caja.',
          'Tip: revisa reportes siempre después del cierre.',
        ],
      ),
      TrainingSection(
        title: 'Módulo 6: Usuarios y permisos (control interno)',
        bullets: [
          'Objetivo: evitar errores y fraudes con permisos correctos.',
          'Práctica: crea perfiles (cajero/supervisor/admin) y limita: edición de precios, anulaciones, reportes.',
          'Implementación recomendada: cualquier acción sensible requiere autorización.',
        ],
      ),
      TrainingSection(
        title: 'Módulo 7: Respaldo y soporte (sin perder información)',
        bullets: [
          'Objetivo: nunca quedarte sin datos.',
          'Práctica: genera un backup, verifica dónde se guardó y crea una copia externa (USB/nube).',
          'Soporte: cuando haya un problema, genera el archivo de soporte y comparte solo con tu técnico.',
        ],
      ),
    ],
  ),
];
