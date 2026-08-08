import { siteConfig } from "@/config/site";

export default function HomePage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-4 px-6 text-center">
      <p className="text-sm uppercase tracking-widest text-accent">{siteConfig.category}</p>
      <h1 className="text-4xl font-semibold">{siteConfig.name}</h1>
      <p className="text-muted-foreground max-w-md">{siteConfig.tagline}</p>
    </main>
  );
}
