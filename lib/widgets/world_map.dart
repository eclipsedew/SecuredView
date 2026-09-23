import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/vpn_models.dart';
import '../theme/app_theme.dart';

class WorldMap extends StatelessWidget {
  final List<ServerConfig> servers;
  final String? selectedId;
  final ValueChanged<ServerConfig> onTap;

  const WorldMap({
    super.key,
    required this.servers,
    this.selectedId,
    required this.onTap,
  });

  // Exact land mask from website network.js — 5-degree grid dots
  // Each row: latitude band starting at 80N stepping down by 5
  // Each band: column ranges where land exists (column c = longitude -180 + c*5)
  static const _landBands = <List<List<int>>>[
    // 80N
    [[14,22],[24,32],[38,39],[45,47],[55,57]],
    // 75N
    [[11,23],[24,32],[47,50],[53,59],[64,66]],
    // 70N
    [[3,23],[25,32],[39,71]],
    // 65N
    [[3,24],[25,33],[37,71]],
    // 60N
    [[3,25],[26,27],[37,71]],
    // 55N
    [[4,5],[9,25],[34,35],[37,71]],
    // 50N
    [[10,25],[34,68]],
    // 45N
    [[11,24],[35,65]],
    // 40N
    [[11,21],[34,61],[63,64]],
    // 35N
    [[12,21],[34,60],[61,64]],
    // 30N
    [[12,20],[32,60]],
    // 25N
    [[13,16],[19,20],[32,60]],
    // 20N
    [[15,16],[19,21],[32,47],[50,57]],
    // 15N
    [[17,19],[21,24],[32,46],[50,53],[55,58],[60,61]],
    // 10N
    [[19,24],[33,45],[51,52],[55,57],[60,61]],
    // 5N
    [[20,25],[34,45],[52,52],[55,59]],
    // 0
    [[20,27],[37,45],[56,63]],
    // 5S
    [[20,29],[38,44],[56,64]],
    // 10S
    [[20,29],[38,44],[59,66]],
    // 15S
    [[21,29],[38,46],[60,65]],
    // 20S
    [[22,28],[38,43],[44,45],[58,66]],
    // 25S
    [[22,27],[38,42],[44,45],[58,66]],
    // 30S
    [[21,26],[39,42],[59,66]],
    // 35S
    [[21,25],[39,41],[59,66],[70,71]],
    // 40S
    [[21,23],[65,65],[70,71]],
    // 45S
    [[21,22],[69,70]],
    // 50S
    [[21,22]],
    // 55S
    [[21,22]],
  ];

  // Site data from website: [city, code, country, cc, lat, lon, nodes, region, plotLabel]
  static const _sites = <_Site>[
    _Site('Accra', 'ACC', 'Ghana', 5.6, -0.19, true),
    _Site('Lagos', 'LOS', 'Nigeria', 6.52, 3.38, false),
    _Site('Nairobi', 'NBO', 'Kenya', -1.29, 36.82, false),
    _Site('Johannesburg', 'JNB', 'South Africa', -26.2, 28.05, true),
    _Site('Cairo', 'CAI', 'Egypt', 30.04, 31.24, false),
    _Site('Casablanca', 'CMN', 'Morocco', 33.57, -7.59, false),
    _Site('Tunis', 'TUN', 'Tunisia', 36.81, 10.18, false),
    _Site('Toronto', 'YYZ', 'Canada', 43.65, -79.38, false),
    _Site('Montreal', 'YUL', 'Canada', 45.5, -73.57, false),
    _Site('New York', 'NYC', 'US', 40.71, -74.01, true),
    _Site('Ashburn', 'IAD', 'US', 39.04, -77.49, false),
    _Site('Chicago', 'ORD', 'US', 41.88, -87.63, false),
    _Site('Dallas', 'DFW', 'US', 32.78, -96.8, false),
    _Site('Denver', 'DEN', 'US', 39.74, -104.99, false),
    _Site('Los Angeles', 'LAX', 'US', 34.05, -118.24, true),
    _Site('Seattle', 'SEA', 'US', 47.61, -122.33, false),
    _Site('Miami', 'MIA', 'US', 25.76, -80.19, false),
    _Site('Mexico City', 'MEX', 'Mexico', 19.43, -99.13, false),
    _Site('Bogota', 'BOG', 'Colombia', 4.71, -74.07, false),
    _Site('Lima', 'LIM', 'Peru', -12.05, -77.04, false),
    _Site('Sao Paulo', 'SAO', 'Brazil', -23.55, -46.63, true),
    _Site('Santiago', 'SCL', 'Chile', -33.45, -70.67, false),
    _Site('Buenos Aires', 'BUE', 'Argentina', -34.6, -58.38, false),
    _Site('Tokyo', 'TYO', 'Japan', 35.68, 139.69, true),
    _Site('Osaka', 'OSA', 'Japan', 34.69, 135.5, false),
    _Site('Seoul', 'SEL', 'South Korea', 37.57, 126.98, false),
    _Site('Hong Kong', 'HKG', 'Hong Kong', 22.32, 114.17, false),
    _Site('Taipei', 'TPE', 'Taiwan', 25.03, 121.57, false),
    _Site('Singapore', 'SIN', 'Singapore', 1.35, 103.82, true),
    _Site('Kuala Lumpur', 'KUL', 'Malaysia', 3.14, 101.69, false),
    _Site('Jakarta', 'CGK', 'Indonesia', -6.21, 106.85, false),
    _Site('Bangkok', 'BKK', 'Thailand', 13.76, 100.5, false),
    _Site('Manila', 'MNL', 'Philippines', 14.6, 120.98, false),
    _Site('Mumbai', 'BOM', 'India', 19.08, 72.88, true),
    _Site('Chennai', 'MAA', 'India', 13.08, 80.27, false),
    _Site('Sydney', 'SYD', 'Australia', -33.87, 151.21, true),
    _Site('Melbourne', 'MEL', 'Australia', -37.81, 144.96, false),
    _Site('Perth', 'PER', 'Australia', -31.95, 115.86, false),
    _Site('Auckland', 'AKL', 'New Zealand', -36.85, 174.76, false),
    _Site('London', 'LON', 'UK', 51.51, -0.13, false),
    _Site('Manchester', 'MAN', 'UK', 53.48, -2.24, false),
    _Site('Dublin', 'DUB', 'Ireland', 53.35, -6.26, false),
    _Site('Amsterdam', 'AMS', 'Netherlands', 52.37, 4.9, true),
    _Site('Frankfurt', 'FRA', 'Germany', 50.11, 8.68, false),
    _Site('Berlin', 'BER', 'Germany', 52.52, 13.4, false),
    _Site('Paris', 'PAR', 'France', 48.86, 2.35, false),
    _Site('Marseille', 'MRS', 'France', 43.3, 5.37, false),
    _Site('Zurich', 'ZRH', 'Switzerland', 47.38, 8.54, false),
    _Site('Vienna', 'VIE', 'Austria', 48.21, 16.37, false),
    _Site('Milan', 'MIL', 'Italy', 45.46, 9.19, false),
    _Site('Madrid', 'MAD', 'Spain', 40.42, -3.7, false),
    _Site('Lisbon', 'LIS', 'Portugal', 38.72, -9.14, false),
    _Site('Brussels', 'BRU', 'Belgium', 50.85, 4.35, false),
    _Site('Copenhagen', 'CPH', 'Denmark', 55.68, 12.57, false),
    _Site('Stockholm', 'STO', 'Sweden', 59.33, 18.07, false),
    _Site('Oslo', 'OSL', 'Norway', 59.91, 10.75, false),
    _Site('Helsinki', 'HEL', 'Finland', 60.17, 24.94, false),
    _Site('Reykjavik', 'REK', 'Iceland', 64.15, -21.94, false),
    _Site('Warsaw', 'WAW', 'Poland', 52.23, 21.01, false),
    _Site('Prague', 'PRG', 'Czechia', 50.08, 14.44, false),
    _Site('Bratislava', 'BTS', 'Slovakia', 48.15, 17.11, false),
    _Site('Budapest', 'BUD', 'Hungary', 47.5, 19.04, false),
    _Site('Bucharest', 'BUH', 'Romania', 44.43, 26.11, false),
    _Site('Sofia', 'SOF', 'Bulgaria', 42.7, 23.32, false),
    _Site('Athens', 'ATH', 'Greece', 37.98, 23.73, false),
    _Site('Tallinn', 'TLL', 'Estonia', 59.44, 24.75, false),
    _Site('Riga', 'RIX', 'Latvia', 56.95, 24.11, false),
    _Site('Vilnius', 'VNO', 'Lithuania', 54.69, 25.28, false),
    _Site('Belgrade', 'BEG', 'Serbia', 44.79, 20.45, false),
    _Site('Zagreb', 'ZAG', 'Croatia', 45.81, 15.98, false),
    _Site('Istanbul', 'IST', 'Turkey', 41.01, 28.98, false),
    _Site('Tel Aviv', 'TLV', 'Israel', 32.09, 34.78, false),
    _Site('Dubai', 'DXB', 'UAE', 25.2, 55.27, true),
    _Site('Doha', 'DOH', 'Qatar', 25.29, 51.53, false),
    _Site('Riyadh', 'RUH', 'Saudi Arabia', 24.71, 46.68, false),
    _Site('Amman', 'AMM', 'Jordan', 31.96, 35.91, false),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return GestureDetector(
          onTapDown: (details) {
            final tapX = details.localPosition.dx;
            final tapY = details.localPosition.dy;
            final svgX = tapX / w * 1440;
            final svgY = tapY / h * 580;
            // Find closest server by coordinates
            ServerConfig? closest;
            double minDist = 25;
            for (final site in _sites) {
              final siteX = (site.lon + 180) * 4;
              final siteY = (85 - site.lat) * 4;
              final dist = math.sqrt(math.pow(svgX - siteX, 2) + math.pow(svgY - siteY, 2));
              if (dist < minDist) {
                // Find closest server config by lat/lon proximity
                for (final server in servers) {
                  final sDist = math.sqrt(
                    math.pow(server.latitude - site.lat, 2) +
                    math.pow(server.longitude - site.lon, 2),
                  );
                  if (sDist < 5) {
                    closest = server;
                    minDist = dist;
                    break;
                  }
                }
              }
            }
            if (closest != null) onTap(closest);
          },
          child: CustomPaint(
            size: Size(w, h),
            painter: _DotMapPainter(
              servers: servers,
              selectedId: selectedId,
              sites: _sites,
              landBands: _landBands,
            ),
          ),
        );
      },
    );
  }
}

class _Site {
  final String city, code, country;
  final double lat, lon;
  final bool plotLabel;
  const _Site(this.city, this.code, this.country, this.lat, this.lon, this.plotLabel);
}

class _DotMapPainter extends CustomPainter {
  final List<ServerConfig> servers;
  final String? selectedId;
  final List<_Site> sites;
  final List<List<List<int>>> landBands;

  _DotMapPainter({
    required this.servers,
    this.selectedId,
    required this.sites,
    required this.landBands,
  });

  // Exact projection from website: px(lon) = (lon + 180) * 4, py(lat) = (85 - lat) * 4
  // ViewBox: 1440 x 580
  static double _px(double lon) => (lon + 180) * 4;
  static double _py(double lat) => (85 - lat) * 4;

  @override
  void paint(Canvas canvas, Size size) {
    const svgW = 1440.0;
    const svgH = 580.0;
    final scaleX = size.width / svgW;
    final scaleY = size.height / svgH;

    // Helper to convert SVG coords to screen coords
    double sx(double svgX) => svgX * scaleX;
    double sy(double svgY) => svgY * scaleY;
    double sr(double r) => r * scaleX;

    // Background — white surface
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = AppTheme.surface,
    );

    // Grid lines — .grat: stroke:var(--line) #d8dcdd
    final gridPaint = Paint()
      ..color = AppTheme.line
      ..strokeWidth = 0.5 * scaleX;

    for (var lon = -180; lon <= 180; lon += 30) {
      final x = sx(_px(lon.toDouble()));
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var lat = 60; lat >= -60; lat -= 30) {
      final y = sy(_py(lat.toDouble()));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Land dots — .land circles with r=3.2 in SVG coords, fill:#c2c8ca
    final landPaint = Paint()
      ..color = AppTheme.line2  // #c2c8ca
      ..style = PaintingStyle.fill;

    final landDotRadius = sr(3.2);

    for (var row = 0; row < landBands.length; row++) {
      final lat = 80.0 - row * 5;
      final y = sy(_py(lat));
      final bands = landBands[row];
      for (final band in bands) {
        for (var c = band[0]; c <= band[1]; c++) {
          final lon = -180.0 + c * 5;
          final x = sx(_px(lon));
          canvas.drawCircle(Offset(x, y), landDotRadius, landPaint);
        }
      }
    }

    // Server pins
    for (final site in sites) {
      final isSelected = servers.any((s) =>
        s.id == selectedId &&
        (s.latitude - site.lat).abs() < 2 &&
        (s.longitude - site.lon).abs() < 2
      );
      final x = sx(_px(site.lon));
      final y = sy(_py(site.lat));

      if (isSelected) {
        // Halo — .halo: fill:var(--blue) opacity:.14, r=11
        final haloPaint = Paint()
          ..color = AppTheme.blue.withValues(alpha: 0.14)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sr(8));
        canvas.drawCircle(Offset(x, y), sr(16), haloPaint);
      }

      // Pin — .pin: fill:var(--blue), r=4
      final pinPaint = Paint()
        ..color = AppTheme.blue
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), sr(isSelected ? 5 : 4), pinPaint);

      // White center for selected
      if (isSelected) {
        final centerPaint = Paint()
          ..color = AppTheme.surface
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(x, y), sr(2), centerPaint);
      }

      // Label for selected — .pcode: font-family:mono, fill:var(--ink-2)
      if (isSelected) {
        final labelPainter = TextPainter(
          text: TextSpan(
            text: ' ${site.code} ',
            style: TextStyle(
              color: AppTheme.ink2,
              fontSize: 11 * scaleX,
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();

        final lx = x + sr(10);
        final ly = y - labelPainter.height / 2;

        // White background pill
        final pillRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(lx - 2, ly - 2, labelPainter.width + 4, labelPainter.height + 4),
          const Radius.circular(2),
        );
        canvas.drawRRect(pillRect, Paint()..color = AppTheme.surface);
        canvas.drawRRect(pillRect, Paint()
          ..color = AppTheme.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 * scaleX);

        labelPainter.paint(canvas, Offset(lx, ly));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotMapPainter oldDelegate) =>
      oldDelegate.selectedId != selectedId;
}
