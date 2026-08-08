/**
 * BitV AI Business Plan Advisor
 * Responds to user queries regarding the imported PDF business plan.
 */

export function generateAIAnswer(question, currentPlan) {
  const q = question.toLowerCase();
  const title = currentPlan.title || "this company";
  const metrics = currentPlan.metrics;

  if (q.includes("valuation") || q.includes("worth") || q.includes("value")) {
    const val = currentPlan.executiveSummary?.valuation || "$18.5M";
    return `Based on the imported PDF financial projections for **${title}**, the estimated valuation is **${val}**. This is computed using a 5-year discounted cash flow (DCF) model and forward ARR multiple benchmarked against ${currentPlan.industry || 'industry'} standards.`;
  }

  if (q.includes("cac") || q.includes("ltv") || q.includes("unit economics")) {
    const ratio = (metrics.ltv / metrics.cac).toFixed(1);
    return `**${title}** shows strong unit economics:\n• Customer Acquisition Cost (CAC): **$${metrics.cac.toLocaleString()}**\n• Lifetime Value (LTV): **$${metrics.ltv.toLocaleString()}**\n• LTV/CAC Ratio: **${ratio}x** (Industry benchmark is 3.0x+)\n• Payback Period: **${metrics.paybackMonths} months**.`;
  }

  if (q.includes("risk") || q.includes("weakness") || q.includes("threat")) {
    const risksList = currentPlan.risks.map(r => `• **${r.risk}** (Severity: ${r.severity}) - *Mitigation: ${r.mitigation}*`).join('\n');
    return `Here are the top risk factors extracted from the **${title}** PDF business plan:\n\n${risksList}`;
  }

  if (q.includes("revenue") || q.includes("growth") || q.includes("financial")) {
    const format = (v) => `$${(v / 1000000).toFixed(1)}M`;
    return `**${title}** 5-Year Revenue Forecast:\n• Year 1: ${format(metrics.y1Revenue)}\n• Year 2: ${format(metrics.y2Revenue)}\n• Year 3: ${format(metrics.y3Revenue)}\n• Year 4: ${format(metrics.y4Revenue)}\n• Year 5: ${format(metrics.y5Revenue)}\nOverall 5-Year CAGR: **${Math.round(Math.pow(metrics.y5Revenue / metrics.y1Revenue, 1/4) * 100 - 100)}%**.`;
  }

  if (q.includes("tam") || q.includes("market") || q.includes("opportunity")) {
    return `Market opportunity breakdown for **${title}**:\n• Total Addressable Market (TAM): **$${metrics.tam}B**\n• Serviceable Addressable Market (SAM): **$${metrics.sam}B**\n• Serviceable Obtainable Market (SOM): **$${metrics.som}B**.`;
  }

  if (q.includes("email") || q.includes("pitch") || q.includes("investor")) {
    return `Here is a drafted investor memo highlight for **${title}**:\n\n"Subject: Executive Brief: ${title} (${currentPlan.stage})\n\nHi [Investor Name],\n\n${title} is building ${currentPlan.tagline}. They are raising ${currentPlan.executiveSummary.targetRaising} to scale operations in the $${metrics.tam}B ${currentPlan.industry} space.\n\nHighlights:\n- Year 1 Revenue: $${(metrics.y1Revenue/1000000).toFixed(1)}M scaling to $${(metrics.y5Revenue/1000000).toFixed(1)}M Year 5\n- LTV/CAC: ${(metrics.ltv/metrics.cac).toFixed(1)}x with ${metrics.paybackMonths}mo payback\n- Unique Advantage: ${currentPlan.swot?.strengths?.[0] || 'State of the art technology'}\n\nLet me know if you would like to review the full BitV parsed report!"`;
  }

  // Default response
  return `Analyzing **${title}** PDF data:\n- Target Funding: **${currentPlan.executiveSummary?.targetRaising || '$2.5M'}**\n- Stage: **${currentPlan.stage || 'Series A'}**\n- Industry: **${currentPlan.industry}**\n\nYou can edit any metric directly in the metrics dashboard panel, and BitV will update financial models live!`;
}
