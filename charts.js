import Chart from 'chart.js/auto';

let revenueChartInstance = null;
let marketChartInstance = null;

/**
 * Render or update 5-Year Revenue Growth Chart
 */
export function renderRevenueChart(canvasId, metrics) {
  const ctx = document.getElementById(canvasId);
  if (!ctx) return;

  if (revenueChartInstance) {
    revenueChartInstance.destroy();
  }

  const formatM = (val) => (val / 1000000).toFixed(1) + 'M';

  const gradient = ctx.getContext('2d').createLinearGradient(0, 0, 0, 300);
  gradient.addColorStop(0, 'rgba(6, 182, 212, 0.4)');
  gradient.addColorStop(1, 'rgba(6, 182, 212, 0.0)');

  revenueChartInstance = new Chart(ctx, {
    type: 'line',
    data: {
      labels: ['Year 1', 'Year 2', 'Year 3', 'Year 4', 'Year 5'],
      datasets: [
        {
          label: 'Projected Revenue ($)',
          data: [
            metrics.y1Revenue,
            metrics.y2Revenue,
            metrics.y3Revenue,
            metrics.y4Revenue,
            metrics.y5Revenue
          ],
          borderColor: '#06b6d4',
          backgroundColor: gradient,
          borderWidth: 3,
          fill: true,
          tension: 0.35,
          pointBackgroundColor: '#6366f1',
          pointBorderColor: '#fff',
          pointRadius: 6,
          pointHoverRadius: 8
        }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          labels: { color: '#94a3b8', font: { family: 'Inter', size: 12 } }
        },
        tooltip: {
          backgroundColor: 'rgba(15, 23, 42, 0.9)',
          titleColor: '#fff',
          bodyColor: '#06b6d4',
          borderColor: 'rgba(255,255,255,0.1)',
          borderWidth: 1,
          callbacks: {
            label: (ctx) => ` Revenue: $${(ctx.raw / 1000000).toFixed(2)} Million`
          }
        }
      },
      scales: {
        x: {
          grid: { color: 'rgba(255, 255, 255, 0.05)' },
          ticks: { color: '#94a3b8', font: { family: 'Inter' } }
        },
        y: {
          grid: { color: 'rgba(255, 255, 255, 0.05)' },
          ticks: {
            color: '#94a3b8',
            font: { family: 'Inter' },
            callback: (val) => '$' + formatM(val)
          }
        }
      }
    }
  });
}

/**
 * Render TAM / SAM / SOM Donut Chart
 */
export function renderMarketChart(canvasId, metrics) {
  const ctx = document.getElementById(canvasId);
  if (!ctx) return;

  if (marketChartInstance) {
    marketChartInstance.destroy();
  }

  marketChartInstance = new Chart(ctx, {
    type: 'doughnut',
    data: {
      labels: ['TAM (Total)', 'SAM (Serviceable)', 'SOM (Obtainable)'],
      datasets: [
        {
          data: [metrics.tam, metrics.sam, metrics.som],
          backgroundColor: [
            'rgba(99, 102, 241, 0.8)',
            'rgba(6, 182, 212, 0.8)',
            'rgba(16, 185, 129, 0.8)'
          ],
          borderColor: '#07090e',
          borderWidth: 3
        }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          position: 'bottom',
          labels: { color: '#94a3b8', font: { family: 'Inter', size: 11 }, padding: 15 }
        },
        tooltip: {
          backgroundColor: 'rgba(15, 23, 42, 0.9)',
          callbacks: {
            label: (ctx) => ` ${ctx.label}: $${ctx.raw}B`
          }
        }
      },
      cutout: '70%'
    }
  });
}
