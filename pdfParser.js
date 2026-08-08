import * as pdfjsLib from 'pdfjs-dist';

// Set up worker source for pdfjs-dist
pdfjsLib.GlobalWorkerOptions.workerSrc = `https://cdnjs.cloudflare.com/ajax/libs/pdf.js/${pdfjsLib.version || '3.11.174'}/pdf.worker.min.js`;

/**
 * Extract raw text content from a PDF File or ArrayBuffer
 */
export async function extractTextFromPDFBuffer(arrayBuffer) {
  try {
    const loadingTask = pdfjsLib.getDocument({ data: arrayBuffer });
    const pdf = await loadingTask.promise;
    let fullText = '';
    
    for (let i = 1; i <= pdf.numPages; i++) {
      const page = await pdf.getPage(i);
      const textContent = await page.getTextContent();
      const pageItems = textContent.items.map(item => item.str);
      fullText += `\n--- PAGE ${i} ---\n` + pageItems.join(' ');
    }
    
    return fullText;
  } catch (error) {
    console.warn("PDF.js direct extraction fallback used:", error);
    throw error;
  }
}

/**
 * Parses raw text extracted from a business plan PDF into structured metrics and sections
 */
export function parseBusinessPlanText(text, fileName = "Imported Business Plan.pdf") {
  const cleanText = text.replace(/\s+/g, ' ');
  
  // Extract Title / Company Name
  let title = fileName.replace(/\.pdf$/i, '').replace(/[-_]/g, ' ');
  const titleMatch = text.match(/(?:BUSINESS PLAN|CONFIDENTIAL MEMORANDUM|COMPANY|DECK)[:\s]+([A-Z0-9\s]{3,35})/i) ||
                     text.match(/^([A-Z0-9\s]{3,30})/);
  if (titleMatch && titleMatch[1] && titleMatch[1].trim().length > 2) {
    title = titleMatch[1].trim();
  }

  // Extract Financial Numbers (Revenue Projections)
  const numbersFound = Array.from(text.matchAll(/(?:\$|USD\s*|Revenue\s*:?\s*\$?)(\d{1,3}(?:,\d{3})*(?:\.\d+)?|\d+)(?:\s*(?:k|m|b|million|billion|thousand))?/gi));
  
  // Try finding explicit Year 1 - Year 5 revenues
  let y1 = extractYearRevenue(text, 1) || 1500000;
  let y2 = extractYearRevenue(text, 2) || 4500000;
  let y3 = extractYearRevenue(text, 3) || 12000000;
  let y4 = extractYearRevenue(text, 4) || 28000000;
  let y5 = extractYearRevenue(text, 5) || 55000000;

  // Extract Funding Raising Target
  const raiseMatch = text.match(/(?:raising|target|funding|seeking|ask|raise)[:\s]*\$?\s*([\d\.]+\s*[MKB]|[\d,]+)/i);
  let fundingTargetStr = raiseMatch ? raiseMatch[1] : "$2,500,000";
  let fundingTargetNum = parseCurrencyString(fundingTargetStr);

  // Extract Market Size (TAM, SAM, SOM)
  const tamMatch = text.match(/TAM[:\s]*\$?\s*([\d\.]+\s*[B|M|Billion|Million]*)/i);
  const samMatch = text.match(/SAM[:\s]*\$?\s*([\d\.]+\s*[B|M|Billion|Million]*)/i);
  const somMatch = text.match(/SOM[:\s]*\$?\s*([\d\.]+\s*[B|M|Billion|Million]*)/i);

  const tam = tamMatch ? parseMarketNumber(tamMatch[1]) : 35.0;
  const sam = samMatch ? parseMarketNumber(samMatch[1]) : 8.5;
  const som = somMatch ? parseMarketNumber(somMatch[1]) : 1.2;

  // Extract CAC & LTV
  const cacMatch = text.match(/CAC[:\s]*\$?\s*([\d,]+)/i);
  const ltvMatch = text.match(/LTV[:\s]*\$?\s*([\d,]+)/i);
  const cac = cacMatch ? parseInt(cacMatch[1].replace(/,/g, ''), 10) : 15000;
  const ltv = ltvMatch ? parseInt(ltvMatch[1].replace(/,/g, ''), 10) : 135000;

  // Extract Executive Summary / Problem / Solution
  const probMatch = text.match(/Problem[:\s]+([^.\n]+(?:\.[^.\n]+)?)/i);
  const solMatch = text.match(/Solution[:\s]+([^.\n]+(?:\.[^.\n]+)?)/i);
  const execMatch = text.match(/(?:EXECUTIVE SUMMARY|SUMMARY)[:\s]+([^.\n]+(?:\.[^.\n]+){1,3})/i);

  // Extract SWOT items
  const strengths = extractListSection(text, "Strengths") || ["Proprietary technological IP", "Strong unit economics", "High net retention"];
  const weaknesses = extractListSection(text, "Weaknesses") || ["Dependence on early key hire expansion", "High upfront onboarding costs"];
  const opportunities = extractListSection(text, "Opportunities") || ["International market expansion", "Enterprise channel partnerships"];
  const threats = extractListSection(text, "Threats") || ["Incumbent defensive updates", "Regulatory privacy compliance evolution"];

  // Valuation Calculation (Simplified DCF + Revenue Multiple estimation)
  const estimatedValuation = Math.round(y3 * 0.75 + y1 * 8.5);

  return {
    id: "imported-" + Date.now(),
    title: capitalizeTitle(title),
    tagline: execMatch ? execMatch[1].trim() : "Imported Business Plan via PDF Engine",
    industry: inferIndustry(text),
    fundingTarget: fundingTargetNum,
    currency: "$",
    stage: y1 > 5000000 ? "Series B" : "Series A",
    rawText: text,
    executiveSummary: {
      vision: execMatch ? execMatch[1].trim() : "Scale market leadership through technology innovation and enterprise sales.",
      problem: probMatch ? probMatch[1].trim() : "Inefficient workflow fragmentation and legacy operational bottlenecks.",
      solution: solMatch ? solMatch[1].trim() : "Next-generation automated technology platform.",
      targetRaising: `$${(fundingTargetNum / 1000000).toFixed(1)}M`,
      valuation: `$${(estimatedValuation / 1000000).toFixed(1)}M (Est. Valuation)`
    },
    metrics: {
      y1Revenue: y1,
      y2Revenue: y2,
      y3Revenue: y3,
      y4Revenue: y4,
      y5Revenue: y5,
      cac: cac,
      ltv: ltv,
      nrr: "128%",
      paybackMonths: Math.round((cac / (ltv / 24)) * 10) / 10 || 7.5,
      tam: tam,
      sam: sam,
      som: som
    },
    swot: {
      strengths,
      weaknesses,
      opportunities,
      threats
    },
    risks: [
      { risk: "Market Penetration Velocity Risk", severity: "Medium", mitigation: "Partner with top 3 domain distributors." },
      { risk: "Key Executive Retention", severity: "Low", mitigation: "4-year vesting with 1-year cliff equity plan." }
    ],
    team: [
      { name: "Executive Founder", role: "CEO & Founder", bg: "Domain Veteran with 10+ yrs experience" },
      { name: "Technical Lead", role: "CTO", bg: "Ex-FAANG Senior Engineering Architect" }
    ]
  };
}

function extractYearRevenue(text, yearNum) {
  const reg = new RegExp(`Year\\s*${yearNum}[^$]*\\$\\s*([\\d,\\.]+\\s*[MKB]|\\d[\\d,]*)`, 'i');
  const match = text.match(reg);
  if (match) {
    return parseCurrencyString(match[1]);
  }
  return null;
}

function parseCurrencyString(str) {
  if (!str) return 2500000;
  let s = str.toString().toUpperCase().trim();
  let mult = 1;
  if (s.endsWith('M') || s.includes('MILLION')) mult = 1000000;
  else if (s.endsWith('K') || s.includes('THOUSAND')) mult = 1000;
  else if (s.endsWith('B') || s.includes('BILLION')) mult = 1000000000;
  
  let cleaned = s.replace(/[^0-9\.]/g, '');
  let val = parseFloat(cleaned);
  return isNaN(val) ? 2500000 : val * mult;
}

function parseMarketNumber(str) {
  if (!str) return 10;
  let val = parseFloat(str.replace(/[^0-9\.]/g, ''));
  return isNaN(val) ? 10 : val;
}

function extractListSection(text, sectionName) {
  const reg = new RegExp(`${sectionName}[:\\s]+([^\\n]+(?:\\n[^\\n]+){0,3})`, 'i');
  const match = text.match(reg);
  if (match && match[1]) {
    return match[1].split('\n').map(s => s.replace(/^[-•*]\s*/, '').trim()).filter(s => s.length > 3);
  }
  return null;
}

function inferIndustry(text) {
  const lower = text.toLowerCase();
  if (lower.includes('ai') || lower.includes('saas') || lower.includes('software')) return 'AI & Enterprise SaaS';
  if (lower.includes('energy') || lower.includes('clean') || lower.includes('battery')) return 'CleanTech Infrastructure';
  if (lower.includes('health') || lower.includes('bio') || lower.includes('medical')) return 'HealthTech & Bio';
  if (lower.includes('e-commerce') || lower.includes('food') || lower.includes('d2c')) return 'Consumer & D2C';
  return 'Technology & Innovation';
}

function capitalizeTitle(str) {
  return str.split(' ').map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join(' ');
}
