import type { NextConfig } from 'next';

/**
 * Security headers applied to every route.
 *
 * CSP is intentionally strict but must allow:
 *  - `unsafe-inline` styles (Tailwind/Radix inject inline style attributes)
 *  - `wss:`/`https:` connect targets (RPC endpoints, WalletConnect relay)
 *  - `frame-src` for wallet connector iframes (Coinbase, WalletConnect)
 *
 * `unsafe-eval` is NOT permitted in production — no dependency in the approved
 * stack requires it, and permitting it would materially weaken XSS containment
 * on a surface where users sign value-bearing transactions.
 */
const securityHeaders = [
  { key: 'X-DNS-Prefetch-Control', value: 'on' },
  { key: 'X-Frame-Options', value: 'DENY' },
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  {
    key: 'Permissions-Policy',
    value: 'camera=(), microphone=(), geolocation=(), interest-cohort=()',
  },
  {
    key: 'Strict-Transport-Security',
    value: 'max-age=63072000; includeSubDomains; preload',
  },
];

const nextConfig: NextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,

  // Fail the production build on type or lint errors. A build that ships
  // known-broken types to a financial surface is not a build worth shipping.
  typescript: { ignoreBuildErrors: false },
  eslint: { ignoreDuringBuilds: false },

  experimental: {
    // Tree-shake barrel imports from these packages to keep client bundles lean.
    optimizePackageImports: ['lucide-react', 'framer-motion', 'date-fns'],
  },

  images: {
    formats: ['image/avif', 'image/webp'],
    remotePatterns: [
      // Token logo CDNs — narrow this list as asset sources are finalised.
      { protocol: 'https', hostname: 'assets.coingecko.com' },
      { protocol: 'https', hostname: 'raw.githubusercontent.com' },
    ],
  },

  async headers() {
    return [{ source: '/:path*', headers: securityHeaders }];
  },

  webpack: (config) => {
    // WalletConnect / wagmi pull in optional native deps that have no browser
    // equivalent. Marking them external prevents bundler resolution failures.
    config.externals.push('pino-pretty', 'lokijs', 'encoding');
    return config;
  },
};

export default nextConfig;
