import { UserRound } from "lucide-react";

function TechnicienCard({ technicien }) {
  const initials = technicien.name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("");

  return (
    <article className="rounded-lg border border-[#222233] bg-[#14141F] p-4 transition-colors duration-200 hover:border-orange-400/50">
      <div className="flex min-w-0 items-start gap-4">
        <span className="inline-flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded bg-[#1E1E2D] text-orange-400">
          {technicien.avatarUrl ? (
            <img src={technicien.avatarUrl} alt={technicien.name} className="h-full w-full rounded object-cover" />
          ) : initials ? (
            <span className="text-[11px] font-bold">{initials}</span>
          ) : (
            <UserRound size={14} />
          )}
        </span>
        <div className="min-w-0">
          <p className="truncate text-sm font-bold leading-tight text-white">{technicien.name}</p>
          <p className="mb-1 truncate text-[10px] font-mono text-slate-500">{technicien.id}</p>
          <p className="truncate text-[10px] text-slate-400">{technicien.email}</p>
        </div>
      </div>
      <div className="mt-3 flex items-center gap-2">
        <button
          type="button"
          className="rounded border border-[#222233] px-3 py-1 text-[9px] text-white transition-colors hover:bg-[#222233]"
          aria-label="Modifier technicien"
        >
          Modifier
        </button>
        <button
          type="button"
          className="rounded border border-[#222233] px-3 py-1 text-[9px] text-white transition-colors hover:bg-[#222233]"
          aria-label="Effacer technicien"
        >
          Effacer
        </button>
      </div>
    </article>
  );
}

export default TechnicienCard;
