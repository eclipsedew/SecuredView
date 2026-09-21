/* SecuredView exit node network: data, map and location table */
(function () {
  'use strict';

  var REGIONS = {
    AF: 'Africa',
    AM: 'Americas',
    AP: 'Asia Pacific',
    EU: 'Europe',
    ME: 'Middle East'
  };

  /* city, code, country, cc, lat, lon, nodes, region, plot label on map */
  var SITES = [
    ['Lagos', 'LOS', 'Nigeria', 'NG', 6.52, 3.38, 26, 'AF', 0],
    ['Nairobi', 'NBO', 'Kenya', 'KE', -1.29, 36.82, 20, 'AF', 0],
    ['Johannesburg', 'JNB', 'South Africa', 'ZA', -26.2, 28.05, 34, 'AF', 1],
    ['Cairo', 'CAI', 'Egypt', 'EG', 30.04, 31.24, 18, 'AF', 0],
    ['Casablanca', 'CMN', 'Morocco', 'MA', 33.57, -7.59, 16, 'AF', 0],
    ['Tunis', 'TUN', 'Tunisia', 'TN', 36.81, 10.18, 12, 'AF', 0],

    ['Toronto', 'YYZ', 'Canada', 'CA', 43.65, -79.38, 48, 'AM', 0],
    ['Montreal', 'YUL', 'Canada', 'CA', 45.5, -73.57, 32, 'AM', 0],
    ['New York', 'NYC', 'United States', 'US', 40.71, -74.01, 96, 'AM', 1],
    ['Ashburn', 'IAD', 'United States', 'US', 39.04, -77.49, 104, 'AM', 0],
    ['Chicago', 'ORD', 'United States', 'US', 41.88, -87.63, 58, 'AM', 0],
    ['Dallas', 'DFW', 'United States', 'US', 32.78, -96.8, 54, 'AM', 0],
    ['Denver', 'DEN', 'United States', 'US', 39.74, -104.99, 26, 'AM', 0],
    ['Los Angeles', 'LAX', 'United States', 'US', 34.05, -118.24, 72, 'AM', 1],
    ['Seattle', 'SEA', 'United States', 'US', 47.61, -122.33, 38, 'AM', 0],
    ['Miami', 'MIA', 'United States', 'US', 25.76, -80.19, 44, 'AM', 0],
    ['Mexico City', 'MEX', 'Mexico', 'MX', 19.43, -99.13, 30, 'AM', 0],
    ['Bogota', 'BOG', 'Colombia', 'CO', 4.71, -74.07, 18, 'AM', 0],
    ['Lima', 'LIM', 'Peru', 'PE', -12.05, -77.04, 14, 'AM', 0],
    ['Sao Paulo', 'SAO', 'Brazil', 'BR', -23.55, -46.63, 52, 'AM', 1],
    ['Santiago', 'SCL', 'Chile', 'CL', -33.45, -70.67, 16, 'AM', 0],
    ['Buenos Aires', 'BUE', 'Argentina', 'AR', -34.6, -58.38, 22, 'AM', 0],

    ['Tokyo', 'TYO', 'Japan', 'JP', 35.68, 139.69, 76, 'AP', 1],
    ['Osaka', 'OSA', 'Japan', 'JP', 34.69, 135.5, 28, 'AP', 0],
    ['Seoul', 'SEL', 'South Korea', 'KR', 37.57, 126.98, 44, 'AP', 0],
    ['Hong Kong', 'HKG', 'Hong Kong', 'HK', 22.32, 114.17, 40, 'AP', 0],
    ['Taipei', 'TPE', 'Taiwan', 'TW', 25.03, 121.57, 26, 'AP', 0],
    ['Singapore', 'SIN', 'Singapore', 'SG', 1.35, 103.82, 84, 'AP', 1],
    ['Kuala Lumpur', 'KUL', 'Malaysia', 'MY', 3.14, 101.69, 22, 'AP', 0],
    ['Jakarta', 'CGK', 'Indonesia', 'ID', -6.21, 106.85, 26, 'AP', 0],
    ['Bangkok', 'BKK', 'Thailand', 'TH', 13.76, 100.5, 24, 'AP', 0],
    ['Manila', 'MNL', 'Philippines', 'PH', 14.6, 120.98, 20, 'AP', 0],
    ['Mumbai', 'BOM', 'India', 'IN', 19.08, 72.88, 56, 'AP', 1],
    ['Chennai', 'MAA', 'India', 'IN', 13.08, 80.27, 24, 'AP', 0],
    ['Sydney', 'SYD', 'Australia', 'AU', -33.87, 151.21, 46, 'AP', 1],
    ['Melbourne', 'MEL', 'Australia', 'AU', -37.81, 144.96, 24, 'AP', 0],
    ['Perth', 'PER', 'Australia', 'AU', -31.95, 115.86, 14, 'AP', 0],
    ['Auckland', 'AKL', 'New Zealand', 'NZ', -36.85, 174.76, 18, 'AP', 0],

    ['London', 'LON', 'United Kingdom', 'GB', 51.51, -0.13, 92, 'EU', 0],
    ['Manchester', 'MAN', 'United Kingdom', 'GB', 53.48, -2.24, 26, 'EU', 0],
    ['Dublin', 'DUB', 'Ireland', 'IE', 53.35, -6.26, 28, 'EU', 0],
    ['Amsterdam', 'AMS', 'Netherlands', 'NL', 52.37, 4.9, 108, 'EU', 2],
    ['Frankfurt', 'FRA', 'Germany', 'DE', 50.11, 8.68, 112, 'EU', 0],
    ['Berlin', 'BER', 'Germany', 'DE', 52.52, 13.4, 34, 'EU', 0],
    ['Paris', 'PAR', 'France', 'FR', 48.86, 2.35, 68, 'EU', 0],
    ['Marseille', 'MRS', 'France', 'FR', 43.3, 5.37, 24, 'EU', 0],
    ['Zurich', 'ZRH', 'Switzerland', 'CH', 47.38, 8.54, 40, 'EU', 0],
    ['Vienna', 'VIE', 'Austria', 'AT', 48.21, 16.37, 26, 'EU', 0],
    ['Milan', 'MIL', 'Italy', 'IT', 45.46, 9.19, 36, 'EU', 0],
    ['Madrid', 'MAD', 'Spain', 'ES', 40.42, -3.7, 38, 'EU', 0],
    ['Lisbon', 'LIS', 'Portugal', 'PT', 38.72, -9.14, 20, 'EU', 0],
    ['Brussels', 'BRU', 'Belgium', 'BE', 50.85, 4.35, 22, 'EU', 0],
    ['Copenhagen', 'CPH', 'Denmark', 'DK', 55.68, 12.57, 24, 'EU', 0],
    ['Stockholm', 'STO', 'Sweden', 'SE', 59.33, 18.07, 42, 'EU', 0],
    ['Oslo', 'OSL', 'Norway', 'NO', 59.91, 10.75, 22, 'EU', 0],
    ['Helsinki', 'HEL', 'Finland', 'FI', 60.17, 24.94, 24, 'EU', 0],
    ['Reykjavik', 'REK', 'Iceland', 'IS', 64.15, -21.94, 12, 'EU', 0],
    ['Warsaw', 'WAW', 'Poland', 'PL', 52.23, 21.01, 30, 'EU', 0],
    ['Prague', 'PRG', 'Czechia', 'CZ', 50.08, 14.44, 26, 'EU', 0],
    ['Bratislava', 'BTS', 'Slovakia', 'SK', 48.15, 17.11, 12, 'EU', 0],
    ['Budapest', 'BUD', 'Hungary', 'HU', 47.5, 19.04, 20, 'EU', 0],
    ['Bucharest', 'BUH', 'Romania', 'RO', 44.43, 26.11, 22, 'EU', 0],
    ['Sofia', 'SOF', 'Bulgaria', 'BG', 42.7, 23.32, 16, 'EU', 0],
    ['Athens', 'ATH', 'Greece', 'GR', 37.98, 23.73, 18, 'EU', 0],
    ['Tallinn', 'TLL', 'Estonia', 'EE', 59.44, 24.75, 14, 'EU', 0],
    ['Riga', 'RIX', 'Latvia', 'LV', 56.95, 24.11, 14, 'EU', 0],
    ['Vilnius', 'VNO', 'Lithuania', 'LT', 54.69, 25.28, 12, 'EU', 0],
    ['Belgrade', 'BEG', 'Serbia', 'RS', 44.79, 20.45, 14, 'EU', 0],
    ['Zagreb', 'ZAG', 'Croatia', 'HR', 45.81, 15.98, 12, 'EU', 0],

    ['Istanbul', 'IST', 'Turkey', 'TR', 41.01, 28.98, 30, 'ME', 0],
    ['Tel Aviv', 'TLV', 'Israel', 'IL', 32.09, 34.78, 22, 'ME', 0],
    ['Dubai', 'DXB', 'United Arab Emirates', 'AE', 25.2, 55.27, 38, 'ME', 1],
    ['Doha', 'DOH', 'Qatar', 'QA', 25.29, 51.53, 16, 'ME', 0],
    ['Riyadh', 'RUH', 'Saudi Arabia', 'SA', 24.71, 46.68, 20, 'ME', 0],
    ['Amman', 'AMM', 'Jordan', 'JO', 31.96, 35.91, 12, 'ME', 0]
  ];

  /* Coarse land mask on a five degree grid. Each row is the band of latitude
     starting at 80N and stepping down by five, holding column ranges where
     land falls. Column c covers longitude -180 + c * 5. */
  var LAND = [
    [[14, 22], [24, 32], [38, 39], [45, 47], [55, 57]],
    [[11, 23], [24, 32], [47, 50], [53, 59], [64, 66]],
    [[3, 23], [25, 32], [39, 71]],
    [[3, 24], [25, 33], [37, 71]],
    [[3, 25], [26, 27], [37, 71]],
    [[4, 5], [9, 25], [34, 35], [37, 71]],
    [[10, 25], [34, 68]],
    [[11, 24], [35, 65]],
    [[11, 21], [34, 61], [63, 64]],
    [[12, 21], [34, 60], [61, 64]],
    [[12, 20], [32, 60]],
    [[13, 16], [19, 20], [32, 60]],
    [[15, 16], [19, 21], [32, 47], [50, 57]],
    [[17, 19], [21, 24], [32, 46], [50, 53], [55, 58], [60, 61]],
    [[19, 24], [33, 45], [51, 52], [55, 57], [60, 61]],
    [[20, 25], [34, 45], [52, 52], [55, 59]],
    [[20, 27], [37, 45], [56, 63]],
    [[20, 29], [38, 44], [56, 64]],
    [[20, 29], [38, 44], [59, 66]],
    [[21, 29], [38, 46], [60, 65]],
    [[22, 28], [38, 43], [44, 45], [58, 66]],
    [[22, 27], [38, 42], [44, 45], [58, 66]],
    [[21, 26], [39, 42], [59, 66]],
    [[21, 25], [39, 41], [59, 66], [70, 71]],
    [[21, 23], [65, 65], [70, 71]],
    [[21, 22], [69, 70]],
    [[21, 22]],
    [[21, 22]]
  ];

  var NS = 'http://www.w3.org/2000/svg';
  var W = 1440, H = 580;
  var px = function (lon) { return (lon + 180) * 4; };
  var py = function (lat) { return (85 - lat) * 4; };

  function el(name, attrs) {
    var node = document.createElementNS(NS, name);
    for (var k in attrs) { node.setAttribute(k, attrs[k]); }
    return node;
  }

  function drawMap(host) {
    var withLabels = host.dataset.map === 'full';
    var svg = el('svg', {
      class: 'map',
      viewBox: '0 0 ' + W + ' ' + H,
      role: 'img',
      'aria-label': 'Exit node locations plotted on a world grid'
    });

    var grat = el('g', { class: 'grat' });
    for (var lon = -180; lon <= 180; lon += 30) {
      grat.appendChild(el('line', { x1: px(lon), y1: 0, x2: px(lon), y2: H }));
    }
    for (var lat = 60; lat >= -60; lat -= 30) {
      grat.appendChild(el('line', { x1: 0, y1: py(lat), x2: W, y2: py(lat) }));
    }
    svg.appendChild(grat);

    var land = el('g', { class: 'land' });
    LAND.forEach(function (bands, row) {
      var y = py(80 - row * 5);
      bands.forEach(function (band) {
        for (var c = band[0]; c <= band[1]; c++) {
          land.appendChild(el('circle', { cx: px(-180 + c * 5), cy: y, r: 3.2 }));
        }
      });
    });
    svg.appendChild(land);

    if (withLabels) {
      var axis = el('g', { class: 'axis' });
      [[-120, '120W'], [-60, '60W'], [0, '0'], [60, '60E'], [120, '120E']].forEach(function (m) {
        axis.appendChild(Object.assign(el('text', {
          x: px(m[0]) + 6, y: H - 8
        }), { textContent: m[1] }));
      });
      svg.appendChild(axis);
    }

    var pins = el('g', {});
    SITES.forEach(function (s) {
      var x = px(s[5]), y = py(s[4]);
      pins.appendChild(el('circle', { class: 'halo', cx: x, cy: y, r: 11 }));
      pins.appendChild(el('circle', { class: 'pin', cx: x, cy: y, r: 4 }));
      if (withLabels && s[8]) {
        var t = el('text', { class: 'pcode', x: x + 13, y: s[8] === 2 ? y - 13 : y + 5 });
        t.textContent = s[1];
        pins.appendChild(t);
      }
    });
    svg.appendChild(pins);

    host.appendChild(svg);
  }

  function buildTable(host) {
    var body = host.querySelector('tbody');
    var filters = document.querySelectorAll('[data-filter]');

    function render(region) {
      body.textContent = '';
      SITES.filter(function (s) { return region === 'all' || s[7] === region; })
        .sort(function (a, b) { return a[0] < b[0] ? -1 : 1; })
        .forEach(function (s) {
          var tr = document.createElement('tr');
          tr.innerHTML =
            '<td class="code">' + s[1] + '</td>' +
            '<td class="name">' + s[0] + '</td>' +
            '<td>' + s[2] + '</td>' +
            '<td>' + REGIONS[s[7]] + '</td>' +
            '<td class="num">' + s[6] + '</td>' +
            '<td class="num">' + (s[6] * 10).toLocaleString('en-US') + '</td>';
          body.appendChild(tr);
        });
    }

    Array.prototype.forEach.call(filters, function (btn) {
      btn.addEventListener('click', function () {
        Array.prototype.forEach.call(filters, function (b) {
          b.setAttribute('aria-pressed', String(b === btn));
        });
        render(btn.dataset.filter);
      });
    });

    render('all');
  }

  function totals() {
    var countries = {}, nodes = 0;
    SITES.forEach(function (s) { countries[s[3]] = 1; nodes += s[6]; });
    return {
      countries: Object.keys(countries).length,
      cities: SITES.length,
      nodes: nodes,
      capacity: Math.round(nodes * 10 / 1000)
    };
  }

  var sums = totals();
  Array.prototype.forEach.call(document.querySelectorAll('[data-net]'), function (node) {
    var v = sums[node.dataset.net];
    if (v !== undefined) { node.textContent = v.toLocaleString('en-US'); }
  });

  Array.prototype.forEach.call(document.querySelectorAll('[data-map]'), drawMap);

  var table = document.getElementById('locations');
  if (table) { buildTable(table); }
})();
