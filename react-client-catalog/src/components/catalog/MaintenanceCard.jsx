import { Wrench } from "lucide-react";

function MaintenanceCard({ agent }) {
  const initials = agent.name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("");

  return (
    <article className="rounded-lg border border-[#222233] bg-[#14141F] p-4 transition-colors duration-200 hover:border-orange-400/50">
      <div className="flex min-w-0 items-start gap-4">
        <span className="inline-flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded bg-[#1E1E2D] text-orange-400">
          {agent.avatarUrl ? (
            <img src={agent.avatarUrl} alt={agent.name} className="h-full w-full rounded object-cover" />
          ) : initials ? (
            <span className="text-[11px] font-bold">{initials}</span>
          ) : (
            <Wrench size={14} />
          )}
        </span>
        <div className="min-w-0">
          <p className="truncate text-sm font-bold leading-tight text-white">{agent.name}</p>
          <p className="mb-1 truncate text-[10px] font-mono text-slate-500">{agent.id}</p>
          <p className="truncate text-[10px] text-slate-400">{agent.email}</p>
        </div>
      </div>
      <div className="mt-3 flex items-center gap-2">
        <button
          type="button"
          className="rounded border border-[#222233] px-3 py-1 text-[9px] text-white transition-colors hover:bg-[#222233]"
          aria-label="Modifier agent maintenance"
        >
          Modifier
        </button>
        <button
          type="button"
          className="rounded border border-[#222233] px-3 py-1 text-[9px] text-white transition-colors hover:bg-[#222233]"
          aria-label="Effacer agent maintenance"
        >
          Effacer
        </button>
      </div>
    </article>
  );
}

export default MaintenanceCard;
