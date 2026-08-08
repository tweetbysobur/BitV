export function EmptyState({ title, description }: { title: string; description?: string }) {
  return (
    <div className="flex flex-col items-start gap-1 rounded-md border border-dashed border-border py-6 pl-4 pr-4 text-sm">
      <p className="font-medium text-foreground">{title}</p>
      {description ? <p className="text-muted-foreground">{description}</p> : null}
    </div>
  );
}
