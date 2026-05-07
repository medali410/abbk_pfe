import { Briefcase } from "lucide-react";

function MachineRow({ machine }) {
  return (
    <article className="rounded-xl border border-[#222233] bg-[#14141F] p-5 transition-colors duration-200 hover:border-orange-400/40">
      <div className="flex min-w-0 items-center gap-5">
        <span className="inline-flex h-14 w-14 shrink-0 items-center justify-center rounded-lg bg-[#1E1E2D] text-orange-400">
          <Briefcase size={24} className="shrink-0" />
        </span>
        <div className="min-w-0">
          <p className="truncate text-base font-bold leading-tight text-white">{machine.name}</p>
          <p className="truncate text-[10px] font-mono uppercase tracking-tight text-slate-500">ID: {machine.id}</p>
        </div>
      </div>
    </article>
  );
}

export default MachineRow;
