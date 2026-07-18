param(
    [string]$ResultsDir = "$PSScriptRoot\bench-results",
    [string]$OutputPath = "$PSScriptRoot\benchmark_dashboard.html"
)

$ErrorActionPreference = "Stop"

function Convert-JsonFile($path) {
    $raw = Get-Content $path -Raw
    $json = $raw | ConvertFrom-Json
    $dirName = (Get-Item $path).Directory.Name
    $json | Add-Member -NotePropertyName "run_dir" -NotePropertyValue $dirName -Force
    $json | Add-Member -NotePropertyName "src_file" -NotePropertyValue $path -Force
    $json.metadata | Add-Member -NotePropertyName "run_dir" -NotePropertyValue $dirName -Force
    return $json
}

Write-Host "Scanning $ResultsDir for .comparison.json files..." -ForegroundColor Cyan
$jsonFiles = Get-ChildItem -Path $ResultsDir -Recurse -Filter "*.comparison.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
if (-not $jsonFiles) { Write-Host "No comparison files found in $ResultsDir" -ForegroundColor Red; exit 1 }
Write-Host "Found $($jsonFiles.Count) results" -ForegroundColor Green

$runs = $jsonFiles | ForEach-Object { Convert-JsonFile $_.FullName }

# ─── Build run history ───────────────────────────────────────────────────
$history = @()
$gatewayBest = @{}
$runIdx = 1
foreach ($run in $runs) {
    $config = $run.metadata.config
    $label = $run.metadata.gateways -join " vs "
    foreach ($gwName in $run.metadata.gateways) {
        $gw = $run.results.$gwName
        if (-not $gw) { continue }
        $entry = @{
            run_num   = $runIdx
            run_label = $label
            run_dir   = $run.run_dir
            timestamp = if ($gw.timestamp) { $gw.timestamp } else { $run.metadata.generated_at }
            gateway   = $gwName
            rps       = [math]::Round($gw.throughput_rps, 2)
            success   = [math]::Round($gw.success_rate, 2)
            p50       = [math]::Round($gw.p50_latency_ms, 2)
            p90       = [math]::Round($gw.p90_latency_ms, 2)
            p95       = [math]::Round($gw.p95_latency_ms, 2)
            p99       = [math]::Round($gw.p99_latency_ms, 2)
            p999      = [math]::Round($gw.p999_latency_ms, 2)
            mean      = [math]::Round($gw.mean_latency_ms, 2)
            max       = [math]::Round($gw.max_latency_ms, 2)
            allocs    = [math]::Round($gw.allocs_per_op, 2)
            bytes     = [math]::Round($gw.bytes_per_op, 0)
            status_200 = $gw.status_200
            errors    = ($gw.error_breakdown | ForEach-Object { "$($_.count)x $($_.message)" }) -join "`n"
            rate      = $config.rate
            duration  = $config.duration_seconds
            model     = $config.model
            endpoint  = $config.endpoint
        }
        $history += $entry

        # Track best per gateway
        $key = $gwName.ToLower()
        if (-not $gatewayBest.ContainsKey($key) -or $entry.rps -gt $gatewayBest[$key].rps) {
            $gatewayBest[$key] = $entry
        }
    }
    $runIdx++
}

# ─── Color palette per gateway ───────────────────────────────────────────
$colorMap = @{
    "aurora"         = "oklch(0.72 0.19 148.99)"
    "aurora-docker"  = "oklch(0.72 0.19 148.99)"
    "gomodel"        = "oklch(0.72 0.15 240)"
    "gomodel-native" = "oklch(0.65 0.15 30)"
    "new-api"        = "oklch(0.55 0.20 0)"
    "default"        = "oklch(0.70 0 0)"
}
function Get-GatewayColor($name) {
    $key = $name.ToLower()
    if ($colorMap.ContainsKey($key)) { return $colorMap[$key] }
    $hash = $key.GetHashCode()
    $h = [math]::Abs($hash) % 360
    return "oklch(0.65 0.15 ${h})"
}

# ─── Best gateways sorted by throughput ──────────────────────────────────
$bestGateways = $gatewayBest.Values | Sort-Object rps -Descending
$maxRps = if ($bestGateways) { $bestGateways[0].rps } else { 6000 }
$maxP99 = if ($bestGateways) { ($bestGateways | ForEach-Object { [math]::Min($_.p99, 500) } | Measure-Object -Maximum).Maximum } else { 500 }

# ─── Generate HTML ───────────────────────────────────────────────────────
$hostname = if ($runs[0].metadata.machine.hostname) { $runs[0].metadata.machine.hostname } else { "localhost" }
$osInfo = if ($runs[0].metadata.machine.os) { $runs[0].metadata.machine.os } else { "Unknown" }
$cpus = if ($runs[0].metadata.machine.logical_processors) { $runs[0].metadata.machine.logical_processors } else { "?" }
$latestRun = $runs[-1]
$peakRps = $bestGateways[0].rps
$bestSuccess = ($bestGateways | Sort-Object success -Descending)[0].success
$bestP99 = ($bestGateways | Sort-Object p99)[0].p99

# JSON-encode history for embedding
$historyJson = $history | ConvertTo-Json -Depth 10 -Compress
$bestGatewaysJson = $bestGateways | ConvertTo-Json -Depth 10 -Compress
$colorMapJson = $colorMap | ConvertTo-Json -Compress

$hostnameSafe = $hostname
$osSafe = $osInfo
$cpusSafe = $cpus
$runCount = $history.Count
$gwCount = $bestGateways.Count

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Aurora Benchmark Dashboard</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js"></script>
  <script src="https://unpkg.com/lucide@latest/dist/umd/lucide.min.js"></script>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300..700&family=JetBrains+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --background: oklch(0.13 0 0);
      --foreground: oklch(0.93 0 0);
      --card: oklch(0.17 0 0);
      --card-hover: oklch(0.20 0 0);
      --primary: oklch(0.72 0.19 148.99);
      --primary-dim: oklch(0.72 0.19 148.99 / 0.15);
      --accent: oklch(0.72 0.19 263.33);
      --accent-dim: oklch(0.72 0.19 263.33 / 0.15);
      --destructive: oklch(0.70 0.22 27.96);
      --destructive-dim: oklch(0.70 0.22 27.96 / 0.15);
      --warning: oklch(0.80 0.20 85.00);
      --warning-dim: oklch(0.80 0.20 85.00 / 0.15);
      --muted: oklch(0.30 0 0);
      --border: oklch(0.25 0 0);
      --radius: 0;
    }
    * { margin: 0; padding: 0; box-sizing: border-box !important; }
    body { font-family:'Space Grotesk',sans-serif; background:var(--background); color:var(--foreground); min-height:100vh; }
    .mono { font-family:'JetBrains Mono',monospace !important; }
    .card { background:var(--card); border:2px solid var(--border); padding:1.5rem; transition:all 0.2s ease; }
    .card:hover { background:var(--card-hover); }
    .stat-value { font-size:1.75rem; font-weight:700; font-family:'JetBrains Mono',monospace; letter-spacing:-0.02em; line-height:1; }
    .stat-label { font-size:0.75rem; color:oklch(0.55 0 0); text-transform:uppercase; letter-spacing:0.08em; font-weight:500; margin-top:0.25rem; }
    .badge { display:inline-flex; align-items:center; gap:0.375rem; padding:0.125rem 0.625rem; font-size:0.7rem; font-weight:600; font-family:'JetBrains Mono',monospace; letter-spacing:0.02em; border:1.5px solid; }
    .badge-green { background:var(--primary-dim); border-color:var(--primary); color:var(--primary); }
    .badge-blue { background:var(--accent-dim); border-color:var(--accent); color:var(--accent); }
    .badge-red { background:var(--destructive-dim); border-color:var(--destructive); color:var(--destructive); }
    .badge-yellow { background:var(--warning-dim); border-color:var(--warning); color:var(--warning); }
    .bar-chart-container { position:relative; height:220px; }
    .progress-bar-track { height:2rem; background:oklch(0.20 0 0); border:1.5px solid var(--border); display:flex; overflow:hidden; }
    .progress-bar-fill { height:100%; transition:width 0.6s ease; display:flex; align-items:center; padding-left:0.75rem; }
    .progress-bar-fill span { font-family:'JetBrains Mono',monospace; font-size:0.75rem; font-weight:600; color:#000; white-space:nowrap; }
    .section-title { font-size:1rem; font-weight:600; text-transform:uppercase; letter-spacing:0.06em; margin-bottom:1.25rem; padding-bottom:0.5rem; border-bottom:2px solid var(--border); }
    table { width:100%; border-collapse:collapse; }
    th { text-align:left; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; color:oklch(0.50 0 0); padding:0.5rem 0.6rem; border-bottom:1.5px solid var(--border); font-weight:600; }
    td { padding:0.5rem 0.6rem; border-bottom:1px solid oklch(0.22 0 0); font-size:0.78rem; }
    tr:hover td { background:oklch(0.20 0 0); }
    .gold { color:oklch(0.85 0.20 85.00); }
    .silver { color:oklch(0.75 0 0); }
    .bronze { color:oklch(0.70 0.15 60.00); }
    ::-webkit-scrollbar { width:6px; }
    ::-webkit-scrollbar-track { background:var(--card); }
    ::-webkit-scrollbar-thumb { background:var(--border); }
    ::-webkit-scrollbar-thumb:hover { background:oklch(0.35 0 0); }
    .tab { padding:0.5rem 1rem; cursor:pointer; font-family:'JetBrains Mono',monospace; font-size:0.75rem; border:1.5px solid var(--border); background:var(--card); color:oklch(0.55 0 0); transition:0.15s; }
    .tab.active { background:var(--primary-dim); border-color:var(--primary); color:var(--primary); }
    .tab:hover { background:var(--card-hover); }
    @media (max-width:768px) { .card { padding:1rem; } .stat-value { font-size:1.25rem; } }
  </style>
</head>
<body>
  <div class="max-w-7xl mx-auto px-4 py-8">
    <!-- Header -->
    <div class="flex items-center justify-between mb-8 flex-wrap gap-4">
      <div>
        <div class="flex items-center gap-3 mb-1">
          <span class="badge badge-green">Auto-Generated</span>
          <span class="text-xs mono" style="color:oklch(0.45 0 0)">$hostnameSafe · $cpusSafe CPUs · $osSafe</span>
        </div>
        <h1 class="text-3xl font-bold tracking-tight" style="font-family:'JetBrains Mono',monospace">Aurora Gateway Benchmark</h1>
        <p class="text-sm mt-1" style="color:oklch(0.55 0 0)">$runCount runs across $gwCount gateways · aggregated from bench-results/</p>
      </div>
      <div class="flex items-center gap-3">
        <span class="badge badge-blue" id="latestDate"></span>
        <span class="badge badge-blue"><span id="runCount">0</span> runs</span>
      </div>
    </div>

    <!-- KPI Row -->
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-8" id="kpiRow"></div>

    <!-- All Gateways Comparison -->
    <div class="card mb-6">
      <div class="section-title">All Gateways · Best Run Comparison</div>
      <div class="overflow-x-auto">
        <table>
          <thead>
            <tr><th>Gateway</th><th>Throughput</th><th>Target%</th><th>Success</th><th>P50</th><th>P90</th><th>P99</th><th>P999</th><th>Mean</th><th>Allocs/op</th><th>Bytes/op</th><th>Run</th></tr>
          </thead>
          <tbody id="comparisonTable"></tbody>
        </table>
      </div>
    </div>

    <!-- Run History -->
    <div class="card mb-6">
      <div class="section-title">Run History · Throughput Evolution</div>
      <div class="flex flex-wrap gap-2 mb-4" id="gatewayTabs"></div>
      <div style="position:relative;height:300px">
        <canvas id="evolutionChart"></canvas>
      </div>
    </div>

    <!-- Detailed History Table -->
    <div class="card mb-6">
      <div class="section-title">All Runs · Detailed</div>
      <div class="overflow-x-auto">
        <table>
          <thead>
            <tr><th>#</th><th>Run</th><th>Gateway</th><th>Throughput</th><th>Success</th><th>P50</th><th>P90</th><th>P99</th><th>P999</th><th>Mean</th><th>Target</th><th>Rate</th><th>Dur</th></tr>
          </thead>
          <tbody id="historyTable"></tbody>
        </table>
      </div>
    </div>

    <!-- Footer -->
    <div class="text-center py-6 text-xs" style="color:oklch(0.35 0 0)">
      <span class="mono">Aurora Gateway Benchmark Dashboard</span> · Generated <span id="genDate"></span> from <span class="mono">bench-results/</span>
    </div>
  </div>

  <script>
    lucide.createIcons();
    const history = $historyJson;
    const bestGateways = $bestGatewaysJson;
    const colorMap = $colorMapJson;

    // ─── Helpers ─────────────────────────────────────────────────────────
    function color(gw) {
      const k = (gw || '').toLowerCase();
      for (const [ck, cv] of Object.entries(colorMap)) {
        if (k.includes(ck)) return cv;
      }
      return 'oklch(0.65 0.15 ' + (Math.abs(k.split('').reduce((a,c)=>a+c.charCodeAt(0),0)) % 300) + ')';
    }
    const fmt = (n, d=1) => typeof n === 'number' ? n.toFixed(d) : n;
    const medals = ['gold','silver','bronze'];

    document.getElementById('runCount').textContent = history.length;

    const dates = history.map(h => h.timestamp).filter(Boolean);
    if (dates.length) {
      const d = new Date(dates[dates.length-1]);
      document.getElementById('latestDate').textContent = d.toLocaleDateString('en-IN', {day:'numeric', month:'short', year:'numeric'});
    }
    document.getElementById('genDate').textContent = new Date().toLocaleString('en-IN');

    // ─── KPI Row ─────────────────────────────────────────────────────────
    const peakRps = Math.max(...bestGateways.map(g => g.rps));
    const bestSuccess = Math.max(...bestGateways.map(g => g.success));
    const bestP99 = Math.min(...bestGateways.map(g => g.p99));
    const bestAllocs = bestGateways.reduce((a,g) => g.allocs < a.allocs ? g : a, bestGateways[0]);
    document.getElementById('kpiRow').innerHTML = [
      { v: peakRps.toLocaleString('en-IN',{maximumFractionDigits:0}), l: 'Peak Throughput (req/s)', c:'var(--primary)' },
      { v: fmt(bestSuccess,2)+'%', l: 'Best Success Rate', c:'var(--primary)' },
      { v: fmt(bestP99,1)+'ms', l: 'Best P99 Latency', c:'var(--accent)' },
      { v: fmt(bestAllocs.allocs,1), l: 'Best Allocs/op', c:'var(--accent)' }
    ].map(k => '<div class="card"><div class="stat-value" style="color:' + k.c + '">' + k.v + '</div><div class="stat-label">' + k.l + '</div></div>').join('');

    // ─── Comparison Table ────────────────────────────────────────────────
    const targetRate = Math.max(...history.map(h => h.rate || 6000));
    const ct = document.getElementById('comparisonTable');
    bestGateways.forEach((g,i) => {
      const pct = (g.rps / (g.rate || targetRate) * 100).toFixed(1);
      const cls = i < 3 ? medals[i] : '';
      ct.innerHTML += '<tr>' +
        '<td class="font-semibold ' + cls + '">' + g.gateway + '</td>' +
        '<td class="mono font-bold" style="color:' + color(g.gateway) + '">' + g.rps.toLocaleString('en-IN',{maximumFractionDigits:0}) + '</td>' +
        '<td class="mono">' + pct + '%</td>' +
        '<td class="mono">' + fmt(g.success,2) + '%</td>' +
        '<td class="mono">' + fmt(g.p50,1) + '</td>' +
        '<td class="mono">' + fmt(g.p90,1) + '</td>' +
        '<td class="mono">' + fmt(g.p99,1) + '</td>' +
        '<td class="mono">' + fmt(g.p999,1) + '</td>' +
        '<td class="mono">' + fmt(g.mean,1) + '</td>' +
        '<td class="mono">' + fmt(g.allocs,1) + '</td>' +
        '<td class="mono">' + g.bytes + '</td>' +
        '<td class="text-xs mono" style="color:oklch(0.50 0 0)">' + (g.run_dir || '') + '</td>' +
        '</tr>';
    });

    // ─── Gateway Tabs ───────────────────────────────────────────────────
    const gateways = [...new Set(history.map(h => h.gateway))];
    const tabs = document.getElementById('gatewayTabs');
    let activeGw = gateways[0] || '';
    gateways.forEach(gw => {
      const btn = document.createElement('button');
      btn.className = 'tab' + (gw === activeGw ? ' active' : '');
      btn.textContent = gw;
      btn.onclick = () => {
        tabs.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        btn.classList.add('active');
        activeGw = gw;
        renderChart();
      };
      tabs.appendChild(btn);
    });

    // ─── Evolution Chart ────────────────────────────────────────────────
    let chart = null;
    function renderChart() {
      const data = history.filter(h => h.gateway === activeGw).sort((a,b) => new Date(a.timestamp) - new Date(b.timestamp));
      if (data.length === 0) return;

      const labels = data.map(h => {
        const d = new Date(h.timestamp);
        return d.toLocaleTimeString('en-IN', {hour:'2-digit',minute:'2-digit'});
      });

      if (chart) { chart.destroy(); chart = null; }

      const ctx = document.getElementById('evolutionChart').getContext('2d');
      chart = new Chart(ctx, {
        type: 'line',
        data: {
          labels,
          datasets: [
            {
              label: 'Throughput (req/s)',
              data: data.map(h => h.rps),
              borderColor: color(activeGw),
              backgroundColor: color(activeGw).replace(')', '/0.12)'),
              fill: true,
              tension: 0.3,
              pointRadius: 5,
              pointHoverRadius: 7,
              pointBackgroundColor: color(activeGw),
              borderWidth: 2,
              yAxisID: 'y',
            },
            {
              label: 'P99 (ms)',
              data: data.map(h => h.p99),
              borderColor: 'var(--accent)',
              backgroundColor: 'oklch(0.72 0.19 263.33 / 0.08)',
              fill: true,
              tension: 0.3,
              pointRadius: 4,
              pointHoverRadius: 6,
              pointBackgroundColor: 'var(--accent)',
              borderWidth: 2,
              yAxisID: 'y1',
            }
          ]
        },
        options: {
          responsive: true, maintainAspectRatio: false,
          interaction: { mode: 'index', intersect: false },
          plugins: {
            legend: { position:'top', labels:{ color:'#aaa', font:{ family:'JetBrains Mono', size:10 }, usePointStyle:true, padding:16 } },
            tooltip: {
              backgroundColor:'oklch(0.13 0 0)', borderColor:'oklch(0.25 0 0)', borderWidth:1.5,
              titleFont:{family:'JetBrains Mono',size:10}, bodyFont:{family:'JetBrains Mono',size:11},
              callbacks: {
                afterBody: function(items) {
                  const idx = items[0].dataIndex;
                  const d = data[idx];
                  return 'Run: ' + (d.run_dir || '') + '\\nTarget: ' + (d.rate||'?') + ' x ' + (d.duration||'?') + 's';
                }
              }
            }
          },
          scales: {
            x: { ticks: { color:'#666', font:{size:9,family:'JetBrains Mono'} }, grid:{color:'oklch(0.20 0 0)'} },
            y: { position:'left', title:{display:true,text:'req/s',color:'#666',font:{family:'JetBrains Mono',size:10}}, ticks:{color:'#666',font:{family:'JetBrains Mono',size:9}}, grid:{color:'oklch(0.20 0 0)'} },
            y1: { position:'right', title:{display:true,text:'P99 (ms)',color:'#666',font:{family:'JetBrains Mono',size:10}}, ticks:{color:'#666',font:{family:'JetBrains Mono',size:9}}, grid:{display:false} }
          }
        }
      });
    }
    renderChart();

    // ─── History Table ──────────────────────────────────────────────────
    const ht = document.getElementById('historyTable');
    const sortedHistory = [...history].sort((a,b) => {
      const da = new Date(a.timestamp), db = new Date(b.timestamp);
      return da - db;
    });
    sortedHistory.forEach((h,i) => {
      const pct = h.rate ? (h.rps / h.rate * 100).toFixed(1) : 'N/A';
      ht.innerHTML += '<tr>' +
        '<td class="mono">' + (i+1) + '</td>' +
        '<td class="text-xs mono" style="color:oklch(0.55 0 0)">' + (h.run_dir||'') + '</td>' +
        '<td class="font-semibold" style="color:' + color(h.gateway) + '">' + h.gateway + '</td>' +
        '<td class="mono font-bold">' + h.rps.toLocaleString('en-IN',{maximumFractionDigits:0}) + '</td>' +
        '<td class="mono">' + fmt(h.success,2) + '%</td>' +
        '<td class="mono">' + fmt(h.p50,1) + '</td>' +
        '<td class="mono">' + fmt(h.p90,1) + '</td>' +
        '<td class="mono">' + fmt(h.p99,1) + '</td>' +
        '<td class="mono">' + fmt(h.p999,1) + '</td>' +
        '<td class="mono">' + fmt(h.mean,1) + '</td>' +
        '<td class="mono">' + pct + '%</td>' +
        '<td class="mono" style="color:oklch(0.50 0 0)">' + (h.rate||'') + '</td>' +
        '<td class="mono" style="color:oklch(0.50 0 0)">' + (h.duration||'') + 's</td>' +
        '</tr>';
    });
  </script>
</body>
</html>
"@

$outputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }

$html | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host ""
Write-Host "Dashboard generated: $OutputPath" -ForegroundColor Green
Write-Host "  Runs: $($history.Count)" -ForegroundColor Cyan
Write-Host "  Gateways: $(($bestGateways | ForEach-Object { $_.gateway }) -join ', ')" -ForegroundColor Cyan
Write-Host "  Peak throughput: $($bestGateways[0].rps) req/s ($($bestGateways[0].gateway))" -ForegroundColor Cyan
