import './style.css';
import { SAMPLE_PLANS } from './samplePlans.js';
import { extractTextFromPDFBuffer, parseBusinessPlanText } from './pdfParser.js';
import { renderRevenueChart, renderMarketChart } from './charts.js';
import { generateAIAnswer } from './aiChat.js';
import { jsPDF } from 'jspdf';

// State management
let currentPlan = SAMPLE_PLANS[0];
let activeTab = 'summary';

const app = document.getElementById('app');

function renderApp() {
  app.innerHTML = `
    <!-- Header -->
    <header class="app-header">
      <a href="#" class="brand-logo">
        <div class="logo-badge">V</div>
        <span>Bit<span class="logo-text-gradient">V</span></span>
      </a>

      <nav class="nav-links">
        <button class="nav-item ${activeTab === 'summary' ? 'active' : ''}" data-tab="summary">Executive Brief</button>
        <button class="nav-item ${activeTab === 'financials' ? 'active' : ''}" data-tab="financials">Financials & Charts</button>
        <button class="nav-item ${activeTab === 'swot' ? 'active' : ''}" data-tab="swot">SWOT & Risks</button>
        <button class="nav-item ${activeTab === 'raw' ? 'active' : ''}" data-tab="raw">Raw PDF Text</button>
        <button class="nav-item ${activeTab === 'ai' ? 'active' : ''}" data-tab="ai">AI Assistant</button>
      </nav>

      <div style="display: flex; gap: 0.75rem;">
        <button id="export-pdf-btn" class="btn-secondary btn-sm">📄 Export PDF Report</button>
        <button id="export-json-btn" class="btn-secondary btn-sm">💾 Export JSON</button>
      </div>
    </header>

    <!-- Main Content Container -->
    <div class="container">
      
      <!-- Top Upload Banner -->
      <section class="hero-banner">
        <h1 class="hero-title">Import & Analyze Business Plans from <span class="logo-text-gradient">PDF</span></h1>
        <p class="hero-subtitle">Upload any startup or corporate business plan in PDF format. BitV extracts key metrics, financial models, market size, and valuation automatically.</p>

        <!-- Dropzone -->
        <div id="pdf-dropzone" class="dropzone">
          <div class="dropzone-icon">
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
              <polyline points="17 8 12 3 7 8"></polyline>
              <line x1="12" y1="3" x2="12" y2="15"></line>
            </svg>
          </div>
          <div class="dropzone-title">Drag & Drop your PDF Business Plan here</div>
          <div class="dropzone-sub">or click to browse local files (.pdf format supported)</div>
          <input type="file" id="pdf-file-input" accept=".pdf" style="display: none;" />
          
          <div class="sample-presets">
            <span style="font-size: 0.85rem; color: var(--text-muted); font-weight: 500;">Or try a pre-loaded sample plan:</span>
            ${SAMPLE_PLANS.map(plan => `
              <button class="sample-preset-btn ${currentPlan.id === plan.id ? 'active' : ''}" data-plan-id="${plan.id}">
                ⚡ ${plan.title} (${plan.stage})
              </button>
            `).join('')}
          </div>
        </div>

        <!-- Parsing Loading Bar -->
        <div id="parsing-status" class="parsing-loader hidden">
          <div class="spinner"></div>
          <div style="font-weight: 600; color: var(--accent-cyan);">Reading PDF document & extracting financial structure...</div>
        </div>
      </section>

      <!-- Active Plan Banner Header -->
      <div class="glass-card p-6 mb-4" style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 1rem;">
        <div>
          <div style="display: flex; align-items: center; gap: 0.75rem;">
            <h2 style="font-size: 1.75rem; font-weight: 800;">${currentPlan.title}</h2>
            <span class="badge badge-cyan">${currentPlan.stage}</span>
            <span class="badge badge-indigo">${currentPlan.industry}</span>
          </div>
          <p style="color: var(--text-secondary); margin-top: 0.25rem;">${currentPlan.tagline}</p>
        </div>
        <div style="text-align: right;">
          <div style="font-size: 0.85rem; color: var(--text-muted); text-transform: uppercase;">Estimated Valuation</div>
          <div style="font-size: 1.85rem; font-weight: 800; color: var(--accent-emerald); font-family: var(--font-heading);">
            ${currentPlan.executiveSummary.valuation}
          </div>
        </div>
      </div>

      <!-- Metric KPI Cards -->
      <div class="metrics-grid">
        <div class="glass-card metric-card">
          <div class="metric-label">Target Funding</div>
          <div class="metric-value" style="color: var(--accent-cyan);">$${(currentPlan.fundingTarget / 1000000).toFixed(2)}M</div>
          <div class="metric-change positive">Seeking capital</div>
        </div>

        <div class="glass-card metric-card">
          <div class="metric-label">Year 1 Revenue</div>
          <div class="metric-value">$${(currentPlan.metrics.y1Revenue / 1000000).toFixed(2)}M</div>
          <div class="metric-change positive">Year 5: $${(currentPlan.metrics.y5Revenue / 1000000).toFixed(0)}M</div>
        </div>

        <div class="glass-card metric-card">
          <div class="metric-label">Unit Economics (LTV / CAC)</div>
          <div class="metric-value">${(currentPlan.metrics.ltv / currentPlan.metrics.cac).toFixed(1)}x</div>
          <div class="metric-change positive">Payback: ${currentPlan.metrics.paybackMonths} mo</div>
        </div>

        <div class="glass-card metric-card">
          <div class="metric-label">Total Market (TAM)</div>
          <div class="metric-value">$${currentPlan.metrics.tam}B</div>
          <div class="metric-change warning">SOM: $${currentPlan.metrics.som}B</div>
        </div>
      </div>

      <!-- Tab Content Area -->
      <div class="tab-content">
        ${renderTabContent()}
      </div>

    </div>
  `;

  attachEventListeners();
  if (activeTab === 'financials') {
    setTimeout(() => {
      renderRevenueChart('revenue-chart-canvas', currentPlan.metrics);
      renderMarketChart('market-chart-canvas', currentPlan.metrics);
    }, 50);
  }
}

function renderTabContent() {
  if (activeTab === 'summary') {
    return `
      <div class="dashboard-grid">
        <!-- Left: Executive Summary -->
        <div class="glass-card p-6">
          <div class="section-header">
            <h3 class="section-title">📌 Executive Overview</h3>
            <span class="badge badge-indigo">Parsed Section</span>
          </div>

          <div style="display: flex; flex-direction: column; gap: 1.25rem;">
            <div>
              <h4 style="color: var(--accent-cyan); font-weight: 600; margin-bottom: 0.25rem;">Core Vision</h4>
              <p style="color: var(--text-secondary);">${currentPlan.executiveSummary.vision}</p>
            </div>

            <div>
              <h4 style="color: var(--accent-rose); font-weight: 600; margin-bottom: 0.25rem;">Problem Addressed</h4>
              <p style="color: var(--text-secondary);">${currentPlan.executiveSummary.problem}</p>
            </div>

            <div>
              <h4 style="color: var(--accent-emerald); font-weight: 600; margin-bottom: 0.25rem;">Proposed Solution</h4>
              <p style="color: var(--text-secondary);">${currentPlan.executiveSummary.solution}</p>
            </div>

            <!-- Founders & Leadership -->
            <div style="margin-top: 1rem;">
              <h4 style="font-weight: 600; margin-bottom: 0.75rem; border-top: 1px solid var(--border-subtle); padding-top: 1rem;">👥 Founding Team & Leadership</h4>
              <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem;">
                ${currentPlan.team ? currentPlan.team.map(member => `
                  <div style="background: rgba(15, 23, 42, 0.6); padding: 0.85rem; border-radius: var(--radius-md); border: 1px solid var(--border-subtle);">
                    <div style="font-weight: 700; color: var(--text-primary);">${member.name}</div>
                    <div style="font-size: 0.8rem; color: var(--accent-cyan);">${member.role}</div>
                    <div style="font-size: 0.8rem; color: var(--text-muted); margin-top: 0.25rem;">${member.bg}</div>
                  </div>
                `).join('') : '<p>Leadership section parsing complete.</p>'}
              </div>
            </div>

          </div>
        </div>

        <!-- Right: Interactive Editable Metrics -->
        <div class="glass-card p-6">
          <div class="section-header">
            <h3 class="section-title">⚙️ Financial Inputs</h3>
            <span class="badge badge-amber">Live Editable</span>
          </div>

          <p style="font-size: 0.85rem; color: var(--text-muted); margin-bottom: 1.25rem;">Adjust values extracted from PDF to re-calculate instant financial models.</p>

          <div style="display: flex; flex-direction: column; gap: 1rem;">
            <div>
              <label style="font-size: 0.8rem; color: var(--text-secondary); display: block; margin-bottom: 0.25rem;">Year 1 Revenue ($)</label>
              <input type="number" id="input-y1" class="editable-input" value="${currentPlan.metrics.y1Revenue}" />
            </div>

            <div>
              <label style="font-size: 0.8rem; color: var(--text-secondary); display: block; margin-bottom: 0.25rem;">Year 5 Target Revenue ($)</label>
              <input type="number" id="input-y5" class="editable-input" value="${currentPlan.metrics.y5Revenue}" />
            </div>

            <div>
              <label style="font-size: 0.8rem; color: var(--text-secondary); display: block; margin-bottom: 0.25rem;">Customer Acquisition Cost (CAC $)</label>
              <input type="number" id="input-cac" class="editable-input" value="${currentPlan.metrics.cac}" />
            </div>

            <div>
              <label style="font-size: 0.8rem; color: var(--text-secondary); display: block; margin-bottom: 0.25rem;">Customer Lifetime Value (LTV $)</label>
              <input type="number" id="input-ltv" class="editable-input" value="${currentPlan.metrics.ltv}" />
            </div>

            <button id="recalculate-btn" class="btn-primary mt-2" style="width: 100%; justify-content: center;">
              🔄 Recalculate Valuation & Model
            </button>
          </div>
        </div>
      </div>
    `;
  }

  if (activeTab === 'financials') {
    return `
      <div class="dashboard-grid">
        <!-- Revenue Growth Line Chart -->
        <div class="glass-card p-6">
          <div class="section-header">
            <h3 class="section-title">📈 5-Year Projected Revenue Growth</h3>
            <span class="badge badge-cyan">Financial Model</span>
          </div>
          <div style="height: 320px; position: relative;">
            <canvas id="revenue-chart-canvas"></canvas>
          </div>
        </div>

        <!-- Market Size Donut Chart -->
        <div class="glass-card p-6">
          <div class="section-header">
            <h3 class="section-title">🎯 Market Opportunity (TAM/SAM/SOM)</h3>
            <span class="badge badge-indigo">Market Size</span>
          </div>
          <div style="height: 320px; position: relative;">
            <canvas id="market-chart-canvas"></canvas>
          </div>
        </div>
      </div>
    `;
  }

  if (activeTab === 'swot') {
    return `
      <div class="glass-card p-6 mb-4">
        <div class="section-header">
          <h3 class="section-title">📊 SWOT Analysis Matrix</h3>
          <span class="badge badge-cyan">Extracted from PDF</span>
        </div>

        <div class="swot-grid">
          <div class="swot-box" style="border-top: 3px solid var(--accent-emerald);">
            <h4 style="color: var(--accent-emerald);">💪 Strengths</h4>
            <ul class="swot-list">
              ${currentPlan.swot.strengths.map(s => `<li>${s}</li>`).join('')}
            </ul>
          </div>

          <div class="swot-box" style="border-top: 3px solid var(--accent-amber);">
            <h4 style="color: var(--accent-amber);">⚠️ Weaknesses</h4>
            <ul class="swot-list">
              ${currentPlan.swot.weaknesses.map(w => `<li>${w}</li>`).join('')}
            </ul>
          </div>

          <div class="swot-box" style="border-top: 3px solid var(--accent-cyan);">
            <h4 style="color: var(--accent-cyan);">🚀 Opportunities</h4>
            <ul class="swot-list">
              ${currentPlan.swot.opportunities.map(o => `<li>${o}</li>`).join('')}
            </ul>
          </div>

          <div class="swot-box" style="border-top: 3px solid var(--accent-rose);">
            <h4 style="color: var(--accent-rose);">🛑 Threats</h4>
            <ul class="swot-list">
              ${currentPlan.swot.threats.map(t => `<li>${t}</li>`).join('')}
            </ul>
          </div>
        </div>
      </div>

      <!-- Risk Factors List -->
      <div class="glass-card p-6">
        <div class="section-header">
          <h3 class="section-title">🛡️ Risk Factors & Mitigation Strategies</h3>
        </div>
        <div style="display: flex; flex-direction: column; gap: 0.85rem;">
          ${currentPlan.risks ? currentPlan.risks.map(r => `
            <div style="background: rgba(15, 23, 42, 0.6); padding: 1rem; border-radius: var(--radius-md); border-left: 4px solid ${r.severity === 'High' ? 'var(--accent-rose)' : 'var(--accent-amber)'};">
              <div style="display: flex; justify-content: space-between; align-items: center;">
                <span style="font-weight: 700; color: var(--text-primary);">${r.risk}</span>
                <span class="badge ${r.severity === 'High' ? 'badge-rose' : 'badge-amber'}">${r.severity} Severity</span>
              </div>
              <p style="font-size: 0.88rem; color: var(--text-secondary); margin-top: 0.35rem;">
                <strong>Mitigation Strategy:</strong> ${r.mitigation}
              </p>
            </div>
          `).join('') : '<p>No critical risks identified.</p>'}
        </div>
      </div>
    `;
  }

  if (activeTab === 'raw') {
    return `
      <div class="glass-card p-6">
        <div class="section-header">
          <h3 class="section-title">📄 Raw PDF Extracted Text</h3>
          <button id="copy-raw-btn" class="btn-secondary btn-sm">📋 Copy Text</button>
        </div>
        <pre class="raw-text-viewer">${escapeHtml(currentPlan.rawText || 'No text extracted.')}</pre>
      </div>
    `;
  }

  if (activeTab === 'ai') {
    return `
      <div class="glass-card p-6">
        <div class="section-header">
          <h3 class="section-title">🤖 AI PDF Business Plan Assistant</h3>
          <span class="badge badge-cyan">Interactive Advisor</span>
        </div>

        <div class="chat-box">
          <div id="chat-messages" class="chat-messages">
            <div class="chat-bubble assistant">
              Hello! I am your BitV AI Advisor. Ask me anything about <strong>${currentPlan.title}</strong>'s business plan, financial model, risks, valuation calculation, or request an investor pitch draft!
            </div>
          </div>
          <div class="chat-input-area">
            <input type="text" id="chat-input" class="chat-input" placeholder="Ask a question about this business plan... (e.g. Is LTV/CAC healthy?)" />
            <button id="send-chat-btn" class="btn-primary btn-sm">Send</button>
          </div>
        </div>
      </div>
    `;
  }

  return '';
}

function attachEventListeners() {
  // Navigation tabs
  document.querySelectorAll('.nav-item').forEach(btn => {
    btn.addEventListener('click', (e) => {
      activeTab = e.target.dataset.tab;
      renderApp();
    });
  });

  // Sample preset buttons
  document.querySelectorAll('.sample-preset-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const planId = e.currentTarget.dataset.planId;
      const found = SAMPLE_PLANS.find(p => p.id === planId);
      if (found) {
        currentPlan = found;
        renderApp();
      }
    });
  });

  // Dropzone click & drag
  const dropzone = document.getElementById('pdf-dropzone');
  const fileInput = document.getElementById('pdf-file-input');

  if (dropzone && fileInput) {
    dropzone.addEventListener('click', (e) => {
      if (!e.target.classList.contains('sample-preset-btn')) {
        fileInput.click();
      }
    });

    dropzone.addEventListener('dragover', (e) => {
      e.preventDefault();
      dropzone.classList.add('dragover');
    });

    dropzone.addEventListener('dragleave', () => {
      dropzone.classList.remove('dragover');
    });

    dropzone.addEventListener('drop', (e) => {
      e.preventDefault();
      dropzone.classList.remove('dragover');
      if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
        handlePDFFile(e.dataTransfer.files[0]);
      }
    });

    fileInput.addEventListener('change', (e) => {
      if (e.target.files && e.target.files.length > 0) {
        handlePDFFile(e.target.files[0]);
      }
    });
  }

  // Recalculate financial model
  const recalcBtn = document.getElementById('recalculate-btn');
  if (recalcBtn) {
    recalcBtn.addEventListener('click', () => {
      const y1 = parseFloat(document.getElementById('input-y1').value) || currentPlan.metrics.y1Revenue;
      const y5 = parseFloat(document.getElementById('input-y5').value) || currentPlan.metrics.y5Revenue;
      const cac = parseFloat(document.getElementById('input-cac').value) || currentPlan.metrics.cac;
      const ltv = parseFloat(document.getElementById('input-ltv').value) || currentPlan.metrics.ltv;

      currentPlan.metrics.y1Revenue = y1;
      currentPlan.metrics.y5Revenue = y5;
      currentPlan.metrics.cac = cac;
      currentPlan.metrics.ltv = ltv;
      currentPlan.metrics.y2Revenue = Math.round(y1 * 2.5);
      currentPlan.metrics.y3Revenue = Math.round(y1 * 5.5);
      currentPlan.metrics.y4Revenue = Math.round(y1 * 10.0);

      const newVal = Math.round(currentPlan.metrics.y3Revenue * 0.75 + y1 * 8.5);
      currentPlan.executiveSummary.valuation = `$${(newVal / 1000000).toFixed(1)}M (Recalculated)`;

      renderApp();
    });
  }

  // AI Chat
  const chatInput = document.getElementById('chat-input');
  const sendChatBtn = document.getElementById('send-chat-btn');
  if (sendChatBtn && chatInput) {
    const handleSend = () => {
      const q = chatInput.value.trim();
      if (!q) return;

      const messagesDiv = document.getElementById('chat-messages');
      const userBubble = document.createElement('div');
      userBubble.className = 'chat-bubble user';
      userBubble.innerText = q;
      messagesDiv.appendChild(userBubble);
      chatInput.value = '';

      setTimeout(() => {
        const answer = generateAIAnswer(q, currentPlan);
        const aiBubble = document.createElement('div');
        aiBubble.className = 'chat-bubble assistant';
        aiBubble.innerHTML = answer.replace(/\n/g, '<br/>');
        messagesDiv.appendChild(aiBubble);
        messagesDiv.scrollTop = messagesDiv.scrollHeight;
      }, 300);
    };

    sendChatBtn.addEventListener('click', handleSend);
    chatInput.addEventListener('keypress', (e) => {
      if (e.key === 'Enter') handleSend();
    });
  }

  // Export JSON
  const exportJsonBtn = document.getElementById('export-json-btn');
  if (exportJsonBtn) {
    exportJsonBtn.addEventListener('click', () => {
      const dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(currentPlan, null, 2));
      const downloadAnchor = document.createElement('a');
      downloadAnchor.setAttribute("href", dataStr);
      downloadAnchor.setAttribute("download", `${currentPlan.title.replace(/\s+/g, '_')}_BitV_Report.json`);
      document.body.appendChild(downloadAnchor);
      downloadAnchor.click();
      downloadAnchor.remove();
    });
  }

  // Export PDF Report
  const exportPdfBtn = document.getElementById('export-pdf-btn');
  if (exportPdfBtn) {
    exportPdfBtn.addEventListener('click', () => {
      const doc = new jsPDF();
      doc.setFontSize(20);
      doc.text(`BitV Analysis Report: ${currentPlan.title}`, 14, 22);
      
      doc.setFontSize(11);
      doc.text(`Industry: ${currentPlan.industry} | Stage: ${currentPlan.stage}`, 14, 30);
      doc.text(`Target Raising: ${currentPlan.executiveSummary.targetRaising} | Valuation: ${currentPlan.executiveSummary.valuation}`, 14, 38);
      
      doc.setFontSize(14);
      doc.text('Financial Highlights', 14, 52);
      doc.setFontSize(10);
      doc.text(`Year 1 Revenue: $${(currentPlan.metrics.y1Revenue/1000000).toFixed(2)}M`, 14, 60);
      doc.text(`Year 5 Revenue: $${(currentPlan.metrics.y5Revenue/1000000).toFixed(2)}M`, 14, 66);
      doc.text(`LTV: $${currentPlan.metrics.ltv} | CAC: $${currentPlan.metrics.cac}`, 14, 72);
      doc.text(`TAM: $${currentPlan.metrics.tam}B | SAM: $${currentPlan.metrics.sam}B | SOM: $${currentPlan.metrics.som}B`, 14, 78);

      doc.setFontSize(14);
      doc.text('Executive Vision', 14, 92);
      doc.setFontSize(10);
      const splitVision = doc.splitTextToSize(currentPlan.executiveSummary.vision, 180);
      doc.text(splitVision, 14, 100);

      doc.save(`${currentPlan.title.replace(/\s+/g, '_')}_BitV_Executive_Brief.pdf`);
    });
  }

  // Copy raw text
  const copyRawBtn = document.getElementById('copy-raw-btn');
  if (copyRawBtn) {
    copyRawBtn.addEventListener('click', () => {
      navigator.clipboard.writeText(currentPlan.rawText || '');
      copyRawBtn.innerText = '✅ Copied!';
      setTimeout(() => copyRawBtn.innerText = '📋 Copy Text', 2000);
    });
  }
}

async function handlePDFFile(file) {
  if (file.type !== 'application/pdf' && !file.name.endsWith('.pdf')) {
    alert("Please upload a valid .pdf document.");
    return;
  }

  const dropzone = document.getElementById('pdf-dropzone');
  const statusLoader = document.getElementById('parsing-status');

  if (dropzone) dropzone.classList.add('hidden');
  if (statusLoader) statusLoader.classList.remove('hidden');

  try {
    const arrayBuffer = await file.arrayBuffer();
    const extractedText = await extractTextFromPDFBuffer(arrayBuffer);
    const parsedPlan = parseBusinessPlanText(extractedText, file.name);

    currentPlan = parsedPlan;
    activeTab = 'summary';
    renderApp();
  } catch (err) {
    console.error("Error reading PDF file:", err);
    alert("Failed to parse PDF file directly. Using intelligent structured text extractor fallback.");
    // Fallback reading
    const textFallback = await file.text().catch(() => "Imported Business Plan PDF document content.");
    currentPlan = parseBusinessPlanText(textFallback, file.name);
    activeTab = 'summary';
    renderApp();
  }
}

function escapeHtml(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// Initial Render
renderApp();
