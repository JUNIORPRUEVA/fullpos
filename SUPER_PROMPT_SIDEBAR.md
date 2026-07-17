# 🚀 SUPER PROMPT - SIDEBAR PREMIUM CON SUBMENÚS (FULLPOS)

## 📋 INSTRUCCIONES

Usa este prompt en otra app (Cursor, Windsurf, Lovable, Bolt, etc.) para **replicar EXACTAMENTE** el sidebar de FULLPOS con un diseño **fino, premium y profesional**. El resultado debe ser **idéntico pixel a pixel** en estilo, animaciones, comportamiento y organización con submenús.

---

## 🎯 OBJETIVO

Crear un **Sidebar premium** con las siguientes características:

1. **Colapsable** con animación suave (280ms easeInOutCubic)
2. **Submenús expandibles** con animación (Clientes → Clientes, Cotizaciones, Créditos | Administración → Compras, Gastos)
3. **Tooltips** cuando está colapsado (OverlayPortal con animación)
4. **Estados**: normal, hover, activo, low emphasis
5. **Gradientes** en items activos con glow/shadow
6. **Header** con logo FULLPOS + toggle button
7. **Secciones**: Principal, Sistema
8. **Responsive**: se adapta a cualquier altura de pantalla
9. **Dark mode** soportado
10. **Escalable**: factor de escala para diferentes tamaños

---

## 🏗️ ARQUITECTURA

```
lib/core/layout/
├── sidebar.dart                    ← Sidebar widget principal
├── widgets/
│   ├── premium_nav_item.dart       ← Item de navegación premium
│   ├── sidebar_header.dart         ← Header con logo y toggle
│   ├── sidebar_section_label.dart  ← Label de sección
│   ├── sidebar_submenu.dart        ← Submenú expandible
│   └── sidebar_tooltip.dart        ← Tooltip para collapsed state
```

---

## 🎨 DISEÑO Y ESTILOS

### Colores (Light Mode)
```dart
// Base
Color sidebarBaseColor = const Color(0xFFF2F6F9);
Color sidebarTextColor = const Color(0xFF1E293B);
Color sidebarMutedTextColor = Color.alphaBlend(sidebarTextColor.withOpacity(0.55), sidebarBaseColor);
Color sidebarHoverColor = Color.alphaBlend(const Color(0xFF2563EB).withOpacity(0.08), sidebarBaseColor);
Color sidebarActiveColor = const Color(0xFF2563EB);
Color sidebarBorderColor = Color.alphaBlend(const Color(0xFFCBD5E1).withOpacity(0.18), sidebarBaseColor);

// Gradientes para item activo
Color sidebarActiveTopColor = Color.alphaBlend(sidebarHighlight(0.10), sidebarActiveColor);
Color sidebarActiveBottomColor = Color.alphaBlend(sidebarShadow(0.18), sidebarActiveColor);

// Tooltip
Color sidebarTooltipColor = const Color(0xFF475569);
Color sidebarTooltipTextColor = ColorUtils.ensureReadableColor(sidebarTextColor, sidebarTooltipColor, minRatio: 4.5);
```

### Colores (Dark Mode)
```dart
Color sidebarBaseColor = const Color(0xFF1E293B);
Color sidebarTextColor = const Color(0xFFE2E8F0);
Color sidebarActiveColor = const Color(0xFF60A5FA);
Color sidebarTooltipColor = const Color(0xFF334155);
```

### Tipografía
- **Font Family**: System default (no requiere Google Fonts)
- **Header**: w700, 13.6px escala, letterSpacing 0.44
- **Header subtitle**: w500, 10px escala, letterSpacing 0.22
- **Nav items**: w700, 12.1px escala, letterSpacing 0.12
- **Section labels**: w700, 8.4px escala, letterSpacing 1.45, UPPERCASE
- **Tooltip**: w700, 16.5px

### Dimensiones
```dart
// Anchos
double expandedWidth = (screenWidth * 0.124).clamp(176.0, 194.0);
double collapsedWidth = (screenWidth * 0.05 * scale).clamp(58.0, 68.0);

// Header
double headerHeight = compact ? topbarHeight - 8 : topbarHeight; // topbarHeight = 52
double brandSize = visualCollapsed ? (40 * scale).clamp(34, 44) : (34 * scale).clamp(30, 38);

// Nav items
double rowHeight = visuallyCollapsed ? (42 * scale).clamp(40, 46) : (38 * scale).clamp(35, 42);
double collapsedIconShellSize = (32 * scale).clamp(30, 36);
double itemRadius = (9 * scale).clamp(7, 9);

// Padding
double railPaddingH = visualCollapsed ? (8 * navScale).clamp(7, 10) : (12 * navScale).clamp(10, 14);
double railPaddingV = visualCollapsed ? (12 * navScale).clamp(10, 14) : (8 * navScale).clamp(6, 10);
double expandedContentMaxWidth = visualCollapsed ? 64 : (168 * navScale).clamp(158, 176);
```

---

## 📦 ESTRUCTURA DE DATOS

### SidebarEntry
```dart
class _SidebarIconPair {
  final IconData outline;
  final IconData filled;
  const _SidebarIconPair({required this.outline, required this.filled});
}

// Entrada principal (sin submenú)
({
  _SidebarIconPair icon,
  String title,
  String route,
  VoidCallback onTap,
})

// Entrada con submenú
({
  _SidebarIconPair icon,
  String title,
  String? route, // null porque no navega directamente
  VoidCallback onTap, // toggle expand
  List<SidebarChildEntry> children,
  Set<String> activeRoutes,
})

// Hijo de submenú
({
  _SidebarIconPair icon,
  String title,
  String route,
})
```

---

## 🧩 COMPONENTES

### 1. Sidebar (Widget Principal)

**Props:**
```dart
class Sidebar extends ConsumerStatefulWidget {
  final bool? forcedCollapsed;
  final double? customWidth;
  final double scale; // default 1.0, clamp 0.65-1.12
}
```

**Estado:**
```dart
bool _isCollapsed = true;
bool _isClientsExpanded = false;
bool _isAdministrationExpanded = false;
AnimationController? _collapseController; // 280ms, easeInOutCubic
```

**Animación de colapso:**
```dart
AnimationController _ensureCollapseController() {
  return _collapseController ??= AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: _isCollapsed ? 1.0 : 0.0,
  );
}

double get _collapseValue {
  final rawValue = _collapseController?.value ?? (_isCollapsed ? 1.0 : 0.0);
  return Curves.easeInOutCubic.transform(rawValue.clamp(0.0, 1.0));
}
```

**Layout:**
```dart
Container(
  height: double.infinity,
  width: currentWidth, // targetWidth + ((collapsedWidth - targetWidth) * collapse)
  clipBehavior: Clip.none,
  decoration: BoxDecoration(
    color: sidebarBaseColor,
    border: Border(right: BorderSide(color: sidebarBorderColor, width: 1)),
    boxShadow: [
      BoxShadow(color: Colors.black.withOpacity(0.14), blurRadius: 22, spreadRadius: -14, offset: Offset(8, 0)),
    ],
  ),
  child: Stack(
    children: [
      // Gradient decorativo de fondo
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [sidebarHighlight(0.04), Colors.transparent, Color(0xFFE2E8F0)],
                stops: [0.0, 0.38, 1.0],
              ),
            ),
          ),
        ),
      ),
      // Contenido principal
      LayoutBuilder(
        builder: (context, constraints) {
          // Calcular escalas y tamaños según altura disponible
          final compactHeight = constraints.maxHeight < 780;
          final ultraCompactHeight = constraints.maxHeight < 690;
          final navScale = (baseScale * (constraints.maxHeight / 860)).clamp(0.72, 1.0);
          
          return Column(
            children: [
              // HEADER
              header,
              // NAVEGACIÓN
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(railPaddingH, railPaddingV, railPaddingH, railPaddingV),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: expandedContentMaxWidth),
                      child: Column(
                        children: [
                          sectionLabel('Principal'),
                          // Items principales sin submenú (Ventas, Productos)
                          buildNavEntry(...),
                          // Item Clientes con submenú
                          buildNavEntry(
                            icon: clientesIcon,
                            title: 'Clientes',
                            route: null,
                            onTap: toggleClientes,
                            activeRoutes: clientesRoutes,
                            trailing: chevronAnimation,
                            showSubmenuBadge: true,
                          ),
                          // Submenú Clientes (animado)
                          AnimatedSize(
                            duration: 240ms,
                            curve: easeOutCubic,
                            child: shouldShowClientsChildren && !visualCollapsed
                              ? Padding(
                                  padding: left(16 * navScale),
                                  child: Column(children: [/* clientChildEntries */]),
                                )
                              : SizedBox.shrink(),
                          ),
                          // Item Reportes
                          buildNavEntry(...),
                          // Separador
                          divider,
                          sectionLabel('Sistema'),
                          // Configuración
                          buildNavEntry(lowEmphasis: true, ...),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ],
  ),
)
```

### 2. PremiumNavItem (Item de Navegación)

**Props:**
```dart
class PremiumNavItem extends StatefulWidget {
  final IconData outlineIcon;
  final IconData activeIcon;
  final String title;
  final String? route;
  final String currentRoute;
  final Set<String>? activeRoutes;
  final VoidCallback? onTap;
  final double collapseProgress; // 0=expanded, 1=collapsed
  final Color textColor;
  final Color activeColor;
  final Color hoverColor;
  final Color surfaceColor;
  final Color tooltipBackgroundColor;
  final Color tooltipTextColor;
  final Color activeGradientStart;
  final Color activeGradientEnd;
  final double scale;
  final bool lowEmphasis; // reduce opacidad
  final bool showTrailingChevron;
  final Widget? trailing;
  final bool showSubmenuBadge; // badge de submenú
}
```

**Estados visuales:**
```dart
// Activo: gradiente + glow + border
// Hover: hoverColor de fondo + shadow suave
// Normal: transparente
// Low emphasis: opacidad 0.6 (cuando no está hover ni activo)
```

**Animaciones:**
```dart
// Hover: AnimatedScale(1.05) + AnimatedContainer(150ms easeInOut)
// Tooltip: AnimatedSlide + AnimatedOpacity (160ms easeInOut)
// Active glow: BoxShadow con blurRadius 20, spreadRadius -8
```

**Tooltip (OverlayPortal):**
```dart
OverlayPortal(
  controller: _tooltipController,
  overlayChildBuilder: (context) {
    return IgnorePointer(
      child: CompositedTransformFollower(
        link: _tooltipLayerLink,
        targetAnchor: Alignment.centerRight,
        followerAnchor: Alignment.centerLeft,
        offset: Offset(tooltipGap, 0),
        child: UnconstrainedBox(
          child: AnimatedSlide(
            offset: _isHover ? Offset.zero : Offset(-0.08, 0),
            child: AnimatedOpacity(
              opacity: _isHover ? 1 : 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 190),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tooltipBackgroundColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tooltipTextColor.withOpacity(0.08)),
                    boxShadow: [BoxShadow(color: shadow(0.28), blurRadius: 20, spreadRadius: -10, offset: Offset(0, 12))],
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Text(title, style: TextStyle(color: tooltipTextColor, fontSize: 16.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  },
  child: CompositedTransformTarget(
    link: _tooltipLayerLink,
    child: Padding(
      padding: EdgeInsets.only(bottom: visuallyCollapsed ? 8 : 5),
      child: MouseRegion(
        cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
        child: AnimatedScale(
          scale: _isHover ? 1.05 : 1.0,
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: itemRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              borderRadius: itemRadius,
              hoverColor: Colors.transparent,
              splashColor: textColor.withOpacity(0.05),
              child: AnimatedContainer(
                duration: 150ms,
                padding: EdgeInsets.symmetric(
                  horizontal: visuallyCollapsed ? 0 : (11 * scale).clamp(9, 13),
                  vertical: visuallyCollapsed ? 0 : (4.5 * scale).clamp(3, 6),
                ),
                decoration: BoxDecoration(
                  color: isActive ? null : (_isHover ? hoverColor : Colors.transparent),
                  gradient: isActive ? LinearGradient(colors: [activeGradientStart, activeGradientEnd]) : null,
                  borderRadius: itemRadius,
                  border: Border.all(color: itemBorderColor),
                  boxShadow: isActive 
                    ? [BoxShadow(color: glowColor.withOpacity(0.42), blurRadius: 20, spreadRadius: -8, offset: Offset(0, 10))]
                    : _isHover 
                      ? [BoxShadow(color: shadow(0.16), blurRadius: 14, spreadRadius: -8, offset: Offset(0, 8))]
                      : [BoxShadow(color: Colors.transparent)],
                ),
                child: Opacity(
                  opacity: contentOpacity,
                  child: SizedBox(
                    height: rowHeight,
                    child: visuallyCollapsed
                      ? _buildCollapsedIcon()
                      : _buildExpandedRow(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
```

**Icono colapsado (con shell decorativo):**
```dart
// Cuando está colapsado, el icono se muestra dentro de un contenedor cuadrado
// con gradiente, borde, sombra y glow si está activo
AnimatedContainer(
  width: collapsedIconShellSize,
  height: collapsedIconShellSize,
  decoration: BoxDecoration(
    gradient: LinearGradient(colors: [collapsedShellTop, collapsedShellBottom]),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: textColor.withOpacity(isActive ? 0.18 : (_isHover ? 0.11 : 0.08))),
    boxShadow: isActive 
      ? [BoxShadow(color: glowColor.withOpacity(0.44), blurRadius: 18, spreadRadius: -8, offset: Offset(0, 8))]
      : [BoxShadow(color: shadow(_isHover ? 0.18 : 0.10), blurRadius: 12, spreadRadius: -8, offset: Offset(0, 8))],
  ),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Stack(
      children: [
        // Highlight gradient
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [navHighlight(isActive ? 0.16 : 0.10), Colors.transparent, navShadow(isActive ? 0.06 : 0.10)],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
        ),
        // Top shine line
        Positioned(left: 8, right: 8, top: 7,
          child: Container(
            height: 1.2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, textColor.withOpacity(isActive ? 0.32 : 0.22), Colors.transparent],
              ),
            ),
          ),
        ),
        // Icon
        Center(
          child: Stack(
            children: [
              PhosphorIcon(isActive ? activeIcon : outlineIcon, color: iconColor, size: 19.5),
              if (showSubmenuBadge) Positioned(right: -5, bottom: -4, child: buildSubmenuBadge()),
            ],
          ),
        ),
      ],
    ),
  ),
)
```

**Fila expandida:**
```dart
Row(
  children: [
    Stack(
      children: [
        PhosphorIcon(isActive ? activeIcon : outlineIcon, color: iconColor, size: 19.5),
        if (showSubmenuBadge) Positioned(right: -6, bottom: -5, child: buildSubmenuBadge()),
      ],
    ),
    if (expanded > 0.001)
      Expanded(
        child: ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: expanded,
            child: Opacity(
              opacity: expanded,
              child: Padding(
                padding: EdgeInsets.only(left: (12 * scale).clamp(8, 11)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title, style: TextStyle(color: fgColor, fontSize: 12.1, fontWeight: FontWeight.w700, letterSpacing: 0.12)),
                    ),
                    if (trailing != null) trailing!
                    else if (showTrailingChevron) PhosphorIcon(caretRight, size: 13.5, color: fgColor.withOpacity(0.58)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
  ],
)
```

### 3. SidebarHeader

**Estados:**
- **Colapsado**: Solo el brand icon centrado, cliqueable para expandir
- **Expandido**: Brand icon + "FULLPOS" + "Sistema comercial" (opcional) + toggle button

**Brand icon:**
```dart
Container(
  width: brandSize,
  height: brandSize,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(14),
    gradient: LinearGradient(
      colors: [Color.alphaBlend(Colors.white.withOpacity(0.08), sidebarBaseColor), Color.alphaBlend(Colors.white.withOpacity(0.02), sidebarBaseColor)],
    ),
    border: Border.all(color: sidebarBorderColor),
    boxShadow: [BoxShadow(color: sidebarShadow(0.16), blurRadius: 14, spreadRadius: -10, offset: Offset(0, 6))],
  ),
  child: Stack(
    children: [
      PhosphorIcon(receipt, size: 19, color: sidebarTextColor),
      Positioned(right: -1.5, bottom: 1, child: PhosphorIcon(creditCard.fill, size: 9.6, color: sidebarActiveColor)),
      if (showCollapsedToggleBadge)
        Positioned(right: -5, bottom: -5, child: badgeCircular),
    ],
  ),
)
```

### 4. SidebarSectionLabel

```dart
Widget sectionLabel(String text) {
  if (!showSectionLabels || expanded <= 0.001) return SizedBox.shrink();
  return ClipRect(
    child: Align(
      alignment: Alignment.centerLeft,
      heightFactor: expanded,
      child: Opacity(
        opacity: expanded,
        child: Padding(
          padding: EdgeInsets.fromLTRB(railPaddingH, 8, railPaddingH, 5),
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              color: sidebarMutedTextColor.withOpacity(0.92),
              fontSize: (8.4 * navScale).clamp(7.8, 9.4),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.45,
            ),
          ),
        ),
      ),
    ),
  );
}
```

### 5. SidebarSubmenu (Animado)

```dart
AnimatedSize(
  duration: const Duration(milliseconds: 240),
  curve: Curves.easeOutCubic,
  alignment: Alignment.topCenter,
  child: shouldShowChildren && !visualCollapsed
    ? Padding(
        padding: EdgeInsets.only(left: (16 * navScale).clamp(12, 18), top: (4 * navScale).clamp(2, 6)),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: shouldShowChildren ? 1 : 0,
          child: Column(
            children: [
              for (final entry in childEntries)
                buildNavEntry(
                  icon: entry.icon,
                  title: entry.title,
                  route: entry.route,
                  onTap: () => _go(context, entry.route),
                  lowEmphasis: true,
                  showTrailingChevron: false,
                ),
            ],
          ),
        ),
      )
    : const SizedBox.shrink(),
)
```

---

## 📋 ENTRADAS DEL MENÚ

### Sección Principal

| Item | Icono (outline/fill) | Ruta | Submenú |
|------|---------------------|------|---------|
| Ventas | `storefront` | `/sales` | No |
| Productos | `package` | `/products` | No |
| **Clientes** | `usersThree` | `null` (toggle) | **Sí** |
| └ Clientes | `userList` | `/clients` | - |
| └ Cotizaciones | `notePencil` | `/quotes-list` | - |
| └ Créditos | `creditCard` | `/credits-list` | - |
| Reportes | `chartBar` | `/reports` | No |
| **Administración** | `squaresFour` | `null` (toggle) | **Sí** |
| └ Compras | `shoppingCart` | `/purchases` | - |
| └ Gastos | `currencyDollar` | `/cash/expenses` | - |

### Sección Sistema

| Item | Icono (outline/fill) | Ruta | Submenú |
|------|---------------------|------|---------|
| Configuración | `gear` | `/settings` | No |

### Iconos (Phosphor Icons)
```dart
// Usar phosphor_flutter package
PhosphorIcons.storefront(PhosphorIconsStyle.regular)    // outline
PhosphorIcons.storefront(PhosphorIconsStyle.fill)        // filled
PhosphorIcons.package(PhosphorIconsStyle.regular)
PhosphorIcons.package(PhosphorIconsStyle.fill)
PhosphorIcons.usersThree(PhosphorIconsStyle.regular)
PhosphorIcons.usersThree(PhosphorIconsStyle.fill)
PhosphorIcons.chartBar(PhosphorIconsStyle.regular)
PhosphorIcons.chartBar(PhosphorIconsStyle.fill)
PhosphorIcons.squaresFour(PhosphorIconsStyle.regular)
PhosphorIcons.squaresFour(PhosphorIconsStyle.fill)
PhosphorIcons.shoppingCart(PhosphorIconsStyle.regular)
PhosphorIcons.shoppingCart(PhosphorIconsStyle.fill)
PhosphorIcons.currencyDollar(PhosphorIconsStyle.regular)
PhosphorIcons.currencyDollar(PhosphorIconsStyle.fill)
PhosphorIcons.gear(PhosphorIconsStyle.regular)
PhosphorIcons.gear(PhosphorIconsStyle.fill)
PhosphorIcons.userList(PhosphorIconsStyle.regular)
PhosphorIcons.userList(PhosphorIconsStyle.fill)
PhosphorIcons.notePencil(PhosphorIconsStyle.regular)
PhosphorIcons.notePencil(PhosphorIconsStyle.fill)
PhosphorIcons.creditCard(PhosphorIconsStyle.regular)
PhosphorIcons.creditCard(PhosphorIconsStyle.fill)
PhosphorIcons.receipt(PhosphorIconsStyle.regular)        // brand icon
PhosphorIcons.caretLeft(PhosphorIconsStyle.bold)          // toggle
PhosphorIcons.caretRight(PhosphorIconsStyle.bold)         // chevron
PhosphorIcons.caretDown(PhosphorIconsStyle.bold)          // submenu badge
```

---

## 🎬 ANIMACIONES DETALLADAS

### Colapso/Expansión (280ms)
```dart
AnimationController(duration: Duration(milliseconds: 280), vsync: this);
Curves.easeInOutCubic
```

### Hover en NavItem (150ms)
```dart
AnimatedScale(duration: 150ms, curve: Curves.easeInOut, scale: _isHover ? 1.05 : 1.0)
AnimatedContainer(duration: 150ms, curve: Curves.easeInOut)
```

### Tooltip (160ms)
```dart
AnimatedSlide(duration: 160ms, curve: Curves.easeInOut, offset: _isHover ? Offset.zero : Offset(-0.08, 0))
AnimatedOpacity(duration: 160ms, curve: Curves.easeInOut, opacity: _isHover ? 1 : 0)
```

### Submenú expandible (240ms)
```dart
AnimatedSize(duration: 240ms, curve: Curves.easeOutCubic)
AnimatedOpacity(duration: 180ms, opacity: shouldShow ? 1 : 0)
```

### Chevron rotación (220ms)
```dart
AnimatedRotation(turns: isExpanded ? 0.25 : 0.0, duration: 220ms, curve: Curves.easeOutCubic)
```

### Header brand icon (180ms)
```dart
AnimatedContainer(duration: 180ms, curve: Curves.easeInOut)
```

---

## ⚡ COMPORTAMIENTO

### Colapso
- **Por defecto**: colapsado (`_isCollapsed = true`)
- **Toggle**: click en brand icon (colapsado) o en botón caretLeft (expandido)
- **Persistencia**: se guarda en `UiPreferences.isSidebarCollapsed`
- **Forzado**: se puede pasar `forcedCollapsed` para control externo

### Submenús
- **Toggle**: click en el item padre
- **Auto-expandir**: si la ruta actual coincide con alguna ruta hija, el submenú se muestra automáticamente
- **Colapsado**: si el sidebar está colapsado, al hacer click en un item con submenú, primero se expande el sidebar y luego se abre el submenú

### Routing
```dart
void _go(BuildContext context, String route) {
  context.go(route);
}

String _safeCurrentPath(BuildContext context) {
  try { return GoRouterState.of(context).uri.path; } catch (_) {}
  try { return GoRouter.of(context).routeInformationProvider.value.uri.path; } catch (_) {}
  return '';
}
```

### Detección de ruta activa
```dart
bool matchesRoute = route != null && (currentRoute == route || currentRoute.startsWith('$route/'));
bool matchesActiveRoute = activeRoutes?.any((r) => currentRoute == r || currentRoute.startsWith('$r/')) ?? false;
bool isActive = matchesRoute || matchesActiveRoute;
```

---

## 📱 RESPONSIVE

### Altura
```dart
bool compactHeight = constraints.maxHeight < 780;
bool ultraCompactHeight = constraints.maxHeight < 690;
double navScale = (baseScale * (constraints.maxHeight / 860)).clamp(0.72, 1.0);
```

### Ancho
```dart
double adaptiveExpandedWidth = (screenSize.width * 0.124).clamp(176.0, 194.0);
double collapsedWidth = (screenSize.width * 0.05 * baseScale).clamp(58.0, 68.0);
```

### Comportamiento en compacto
- Ocultar subtitle del header
- Ocultar section labels
- Ocultar trailing chevrons
- Reducir paddings y tamaños

---

## 🛠️ DEPENDENCIAS

```yaml
dependencies:
  flutter_riverpod: ^2.4.0
  go_router: ^14.0.0
  phosphor_flutter: ^2.1.0
```

---

## ✅ LISTA DE VERIFICACIÓN FINAL

- [ ] **Header**: brand icon con gradiente, borde, sombra, badge de toggle cuando colapsado
- [ ] **Header expandido**: brand icon + "FULLPOS" + "Sistema comercial" + botón toggle
- [ ] **Section labels**: "PRINCIPAL" y "SISTEMA" con animación fade
- [ ] **Nav items**: icono + texto + chevron trailing (opcional)
- [ ] **Estados**: normal, hover (scale 1.05 + shadow), activo (gradiente + glow), low emphasis (opacidad 0.6)
- [ ] **Submenú Clientes**: Clientes, Cotizaciones, Créditos con animación expandible
- [ ] **Submenú Administración**: Compras, Gastos con animación expandible
- [ ] **Tooltips**: cuando sidebar está colapsado, mostrar tooltip con OverlayPortal
- [ ] **Animaciones**: colapso 280ms, hover 150ms, tooltip 160ms, submenú 240ms, chevron 220ms
- [ ] **Responsive**: se adapta a altura y ancho de pantalla
- [ ] **Dark mode**: colores diferentes para dark/light
- [ ] **Persistencia**: estado colapsado guardado en SharedPreferences
- [ ] **Routing**: integración con GoRouter
- [ ] **Ruta activa**: detección automática con soporte de rutas hijas
- [ ] **Iconos Phosphor**: todos los iconos correctos con outline/fill

---

## 🎯 NOTAS IMPORTANTES

1. **Usar `AnimatedBuilder`** con el `AnimationController` para animar el ancho del sidebar
2. **Usar `LayoutBuilder`** para detectar el tamaño disponible y adaptar la UI
3. **Usar `OverlayPortal`** para los tooltips (no `Tooltip` widget)
4. **Usar `CompositedTransformTarget` + `CompositedTransformFollower`** para posicionar tooltips
5. **Los colores deben calcularse con `Color.alphaBlend`** para mezclar correctamente
6. **Usar `ColorUtils.ensureReadableColor`** para garantizar contraste legible
7. **El factor de escala `scale`** debe estar clamp entre 0.65 y 1.12
8. **El `navScale`** debe calcularse en base a la altura disponible (maxHeight / 860)
9. **Los submenús deben auto-expandirse** si la ruta actual coincide con alguna ruta hija
10. **Cuando el sidebar está colapsado y se hace click en un item con submenú**, primero expandir el sidebar y luego abrir el submenú
