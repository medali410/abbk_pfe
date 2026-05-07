import { UserRound } from "lucide-react";

function TechnicienCard({ technicien }) {
  const initials = technicien.name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("");

  return (
    <article className="rounded-xl border border-blue-200/60 bg-white/60 p-4 shadow-sm shadow-blue-200/30 backdrop-blur-sm transition-colors duration-200 hover:border-orange-400/60 hover:bg-white/80">
      <div className="flex min-w-0 items-start gap-4">
        <span className="inline-flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded-lg bg-blue-100/70 text-orange-500">
          {technicien.avatarUrl ? (
            <img src={technicien.avatarUrl} alt={technicien.name} className="h-full w-full rounded-lg object-cover" />
          ) : initials ? (
            <span className="text-[11px] font-bold">{initials}</span>
          ) : (
            <UserRound size={14} />
          )}
        </span>
        <div className="min-w-0">
          <p className="truncate text-sm font-bold leading-tight text-blue-950">{technicien.name}</p>
          <p className="mb-1 truncate text-[10px] font-mono text-blue-700/70">{technicien.id}</p>
          <p className="truncate text-[10px] text-slate-600">{technicien.email}</p>
        </div>
      </div>
      <div className="mt-3 flex items-center gap-2">
        <button
          type="button"
          className="rounded-lg border border-blue-200/70 bg-white/60 px-3 py-1 text-[9px] font-semibold text-blue-900 transition-colors hover:bg-blue-100/70"
          aria-label="Modifier technicien"
        >
          Modifier
        </button>
        <button
          type="button"
          className="rounded-lg border border-blue-200/70 bg-white/60 px-3 py-1 text-[9px] font-semibold text-blue-900 transition-colors hover:bg-blue-100/70"
          aria-label="Effacer technicien"
        >
          Effacer
        </button>
      </div>
    </article>
  );
}

export default TechnicienCard;
