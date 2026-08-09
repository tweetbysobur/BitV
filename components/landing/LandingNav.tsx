"use client";

import { useState } from "react";
import Link from "next/link";
import { Menu, X } from "lucide-react";
import { BitVLockup } from "@/components/brand/BitVMark";
import { buttonVariants } from "@/components/ui/button";

const LINKS = [
  { label: "Protocol", href: "#protocol" },
  { label: "Risk", href: "#risk" },
  { label: "RWA", href: "#rwa" },
  { label: "Vaults", href: "#vaults" },
  {
    label: "Docs",
    href: "https://github.com/tweetbysobur/BitV/tree/main/docs",
    external: true,
  },
];

export function LandingNav() {
  const [open, setOpen] = useState(false);

  return (
    <header className="sticky top-0 z-50 border-b border-border bg-background/80 backdrop-blur">
      <nav className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
        <Link href="/" aria-label="BitV home">
          <BitVLockup />
        </Link>

        <div className="hidden items-center gap-8 md:flex">
          {LINKS.map((link) =>
            link.external ? (
              <a
                key={link.label}
                href={link.href}
                target="_blank"
                rel="noreferrer noopener"
                className="text-sm text-muted-foreground transition-colors hover:text-foreground"
              >
                {link.label}
              </a>
            ) : (
              <a
                key={link.label}
                href={link.href}
                className="text-sm text-muted-foreground transition-colors hover:text-foreground"
              >
                {link.label}
              </a>
            )
          )}
        </div>

        <div className="hidden md:block">
          <Link href="/dashboard" className={buttonVariants("primary")}>
            Launch App
          </Link>
        </div>

        <button
          type="button"
          aria-label={open ? "Close menu" : "Open menu"}
          className="text-foreground md:hidden"
          onClick={() => setOpen((v) => !v)}
        >
          {open ? <X size={22} /> : <Menu size={22} />}
        </button>
      </nav>

      {open && (
        <div className="border-t border-border px-6 py-4 md:hidden">
          <div className="flex flex-col gap-4">
            {LINKS.map((link) =>
              link.external ? (
                <a
                  key={link.label}
                  href={link.href}
                  target="_blank"
                  rel="noreferrer noopener"
                  className="text-sm text-muted-foreground hover:text-foreground"
                  onClick={() => setOpen(false)}
                >
                  {link.label}
                </a>
              ) : (
                <a
                  key={link.label}
                  href={link.href}
                  className="text-sm text-muted-foreground hover:text-foreground"
                  onClick={() => setOpen(false)}
                >
                  {link.label}
                </a>
              )
            )}
            <Link
              href="/dashboard"
              className={buttonVariants("primary", "mt-2 w-full")}
              onClick={() => setOpen(false)}
            >
              Launch App
            </Link>
          </div>
        </div>
      )}
    </header>
  );
}
