/**
 * BitV Sample Business Plans
 * Pre-configured realistic PDF business plans for instant import & testing.
 */

export const SAMPLE_PLANS = [
  {
    id: "apex-ai",
    title: "Apex AI Technologies",
    tagline: "Autonomous Enterprise Knowledge & Decision Engine",
    industry: "Enterprise AI / B2B SaaS",
    fundingTarget: 3500000,
    currency: "$",
    stage: "Series A",
    rawText: `APEX AI TECHNOLOGIES INC. - BUSINESS PLAN & FINANCIAL PROJECTIONS (2026-2030)
CONFIDENTIAL MEMORANDUM - FOR INVESTOR REVIEW ONLY

1. EXECUTIVE SUMMARY
Apex AI provides an enterprise-grade agentic knowledge workflow engine that connects fragmented company databases (Salesforce, Jira, Slack, Notion) with LLM automation. Our proprietary retrieval architecture reduces manual research time for enterprise analysts by 78%.

Problem: Fortune 500 knowledge workers waste 12.5 hours per week searching for internal documentation and synthesizing cross-department reports.
Solution: Autonomous AI agents that search, verify, summarize, and trigger multi-step cross-platform workflows with human-in-the-loop safety.

Target Raising: $3.5M Series A for engineering expansion and enterprise sales scale.
Pre-Money Valuation: $18.5M based on 10.2x forward ARR multiple.

2. MARKET OPPORTUNITY & TAM / SAM / SOM
- Total Addressable Market (TAM): $48.5B Global Enterprise Knowledge Management Software.
- Serviceable Addressable Market (SAM): $12.2B Enterprise Knowledge Graph & AI Assistant market.
- Serviceable Obtainable Market (SOM): $1.4B Financial & Healthcare vertical focused enterprise software.

3. FINANCIAL PROJECTIONS (USD)
- Year 1 (2026): Revenue $1,200,000 | COGS $240,000 | OPEX $1,600,000 | EBITDA -$640,000
- Year 2 (2027): Revenue $4,800,000 | COGS $860,000 | OPEX $2,800,000 | EBITDA $1,140,000
- Year 3 (2028): Revenue $14,500,000 | COGS $2,300,000 | OPEX $5,200,000 | EBITDA $7,000,000
- Year 4 (2029): Revenue $32,000,000 | COGS $4,800,000 | OPEX $9,500,000 | EBITDA $17,700,000
- Year 5 (2030): Revenue $65,000,000 | COGS $9,100,000 | OPEX $18,000,000 | EBITDA $37,900,000

Key Unit Economics:
- Customer Acquisition Cost (CAC): $18,400
- Lifetime Value (LTV): $165,000 (LTV/CAC = 8.9x)
- Average Annual Contract Value (ACV): $45,000
- Net Revenue Retention (NRR): 132%
- Payback Period: 6.2 months

4. SWOT ANALYSIS
Strengths:
- Patent-pending vector-relational indexing pipeline.
- SOC2 Type II and HIPAA compliant infrastructure.
- 132% NRR driven by seat expansion in existing accounts.

Weaknesses:
- High initial compute GPU costs during enterprise model fine-tuning.
- Enterprise sales cycle currently averages 90 days.

Opportunities:
- Federal government & defense intelligence market expansion.
- Automated API integrations marketplace for third-party developers.

Threats:
- Incumbents (Microsoft Copilot, Salesforce Agentforce) bunding basic search.
- Fast-evolving LLM API pricing volatility.

5. RISK ANALYSIS & MITIGATION
- Risk 1: Model Hallucination in regulated industries (Severity: High). Mitigation: Strict citation verification layer requiring source link validation for every output sentence.
- Risk 2: High Customer Churn if adoption stalls (Severity: Medium). Mitigation: Dedicated Customer Success Engineers assigned to all contracts >$50k.

6. FOUNDING TEAM
- Dr. Elena Vance (CEO) - Ex-Google Brain AI Research Lead, PhD Stanford.
- Marcus Brody (CTO) - Former Principal Architect at Snowflake.
- Sarah Lin (VP Sales) - Scaled Enterprise ARR at Datadog from $5M to $40M.`,

    executiveSummary: {
      vision: "Empower Fortune 500 teams with zero-latency autonomous knowledge agents.",
      problem: "Knowledge workers spend 12.5 hrs/week hunting for internal documents across siloed tools.",
      solution: "Agentic knowledge graph engine connecting Salesforce, Jira, Notion with enterprise LLMs.",
      targetRaising: "$3.5M Series A",
      valuation: "$18.5M Pre-Money"
    },

    metrics: {
      y1Revenue: 1200000,
      y2Revenue: 4800000,
      y3Revenue: 14500000,
      y4Revenue: 32000000,
      y5Revenue: 65000000,
      cac: 18400,
      ltv: 165000,
      nrr: "132%",
      paybackMonths: 6.2,
      tam: 48.5, // in Billions
      sam: 12.2,
      som: 1.4
    },

    swot: {
      strengths: ["Patent-pending indexing pipeline", "SOC2 Type II & HIPAA compliance", "132% NRR"],
      weaknesses: ["High GPU compute overhead during setup", "90-day enterprise sales cycle"],
      opportunities: ["GovSec & Defense expansion", "Developer integrations ecosystem"],
      threats: ["Big Tech bundled copilots", "API cost volatility"]
    },

    risks: [
      { risk: "LLM Hallucinations in Financial Statements", severity: "High", mitigation: "Strict deterministic source link validation engine." },
      { risk: "Enterprise Adoption Deadlocks", severity: "Medium", mitigation: "White-glove onboarding engineers assigned to all enterprise pilots." }
    ],

    team: [
      { name: "Dr. Elena Vance", role: "Co-Founder & CEO", bg: "Ex-Google Brain AI Lead, PhD Stanford" },
      { name: "Marcus Brody", role: "Co-Founder & CTO", bg: "Former Principal Architect at Snowflake" },
      { name: "Sarah Lin", role: "VP of Sales", bg: "Scaled Datadog ARR from $5M to $40M" }
    ]
  },

  {
    id: "greengrid",
    title: "GreenGrid Energy Solutions",
    tagline: "Next-Gen Thermal Battery & Distributed Microgrid Storage",
    industry: "CleanTech & Hardware Infrastructure",
    fundingTarget: 8000000,
    currency: "$",
    stage: "Series B",
    rawText: `GREENGRID ENERGY SOLUTIONS - BUSINESS PLAN 2026
EXECUTIVE BRIEF & INFRASTRUCTURE EXPANSION

1. EXECUTIVE SUMMARY
GreenGrid Energy manufactures high-density solid-state thermal energy storage systems that convert excess industrial waste heat and solar energy into 24/7 firm dispatchable electricity.

Problem: Renewable energy intermittency causes massive grid curtailment and high peak demand electricity costs for manufacturing plants.
Solution: Modular, scalable solid-state thermal battery containers storing energy up to 1400°C with 94% round-trip efficiency.

Funding Goal: $8.0M Series B to scale manufacturing facility in Ohio and deliver existing $22M contract backlog.
Valuation: $42.0M Post-Money Valuation.

2. MARKET SIZE & TAM/SAM/SOM
- TAM: $120.0B Global Grid-Scale Energy Storage Market by 2030.
- SAM: $28.5B Industrial Thermal Energy & Peak Shaving Market.
- SOM: $3.2B North American Heavy Manufacturing & Steel Mills sector.

3. FINANCIAL FORECAST (USD)
- Year 1: $3,500,000 | EBITDA -$1,200,000
- Year 2: $12,800,000 | EBITDA $1,400,000
- Year 3: $38,000,000 | EBITDA $8,600,000
- Year 4: $85,000,000 | EBITDA $22,100,000
- Year 5: $160,000,000 | EBITDA $46,500,000

Key Unit Economics:
- Hardware Gross Margin: 42%
- Hardware CAC: $45,000
- Average Project Value: $1.8M
- Payback Period: 14 months

4. SWOT & RISKS
Strengths: 94% round-trip efficiency, non-lithium abundant materials (silicon-aluminum alloy).
Weaknesses: High initial CapEx requirement per factory line.
Risks: Raw material commodity price spikes (Mitigation: Long-term hedging supply contracts).`,

    executiveSummary: {
      vision: "Eliminate industrial renewable curtailment with high-density thermal storage.",
      problem: "Heavy industry pays extreme peak demand surges due to renewable energy intermittency.",
      solution: "Modular thermal battery containers delivering dispatchable 1400°C power.",
      targetRaising: "$8.0M Series B",
      valuation: "$42.0M Post-Money"
    },

    metrics: {
      y1Revenue: 3500000,
      y2Revenue: 12800000,
      y3Revenue: 38000000,
      y4Revenue: 85000000,
      y5Revenue: 160000000,
      cac: 45000,
      ltv: 1800000,
      nrr: "118%",
      paybackMonths: 14.0,
      tam: 120.0,
      sam: 28.5,
      som: 3.2
    },

    swot: {
      strengths: ["94% round-trip energy efficiency", "Non-toxic abundant raw materials", "$22M signed backlog"],
      weaknesses: ["High CapEx factory tooling requirements", "Complex site installation permits"],
      opportunities: ["US IRA Clean Energy Tax Credit subsidies (40% ITC)", "EU Green Transition mandates"],
      threats: ["Lithium-ion price drops", "Grid interconnect bottleneck delays"]
    },

    risks: [
      { risk: "Supply Chain Commodity Inflation", severity: "Medium", mitigation: "Locked 3-year supply hedging agreements with domestic metal suppliers." }
    ],

    team: [
      { name: "Dr. Vikram Patel", role: "CEO", bg: "Former Principal Engineer at Tesla Energy & ARPA-E" },
      { name: "Claire Dupont", role: "COO", bg: "Ex-GE Renewable Power Plant Manager" }
    ]
  }
];
