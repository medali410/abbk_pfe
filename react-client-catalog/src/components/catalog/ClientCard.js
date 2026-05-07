function ClientCard({ client, isOpen }) {
  const initials = client.name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("");
  const hasAvatar = Boolean(client.avatarUrl);

  return (
    <article
      className={`rounded-xl border p-5 transition-all duration-200 ${
        isOpen
          ? "border-orange-400/70 bg-[#14141F] ring-1 ring-orange-400/40"
          : "border-[#222233] bg-[#14141F] hover:border-orange-400/50"
      }`}
    >
      <div>
        <div className="mb-4 flex items-center gap-4">
          {hasAvatar ? (
            <img
              src={client.avatarUrl}
              alt={`Avatar de ${client.name}`}
              className={`h-12 w-12 shrink-0 rounded-full object-cover ${
                isOpen ? "border border-orange-400" : "border border-[#222233]"
              }`}
              loading="lazy"
            />
          ) : (
            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full border border-[#222233] bg-[#1E1E2D] text-xs font-bold text-orange-400">
              {initials || "CL"}
            </div>
          )}
          <div className="min-w-0">
            <h3
              className={`truncate text-lg font-bold leading-tight transition-colors duration-200 ${
                isOpen ? "text-orange-400" : "text-white"
              }`}
            >
              {client.name}
            </h3>
            <p className={`text-[10px] font-mono uppercase ${isOpen ? "text-slate-300" : "text-slate-400"}`}>
              ID: {client.id}
            </p>
          </div>
        </div>
        <p className={`mb-5 truncate text-xs ${isOpen ? "text-slate-400" : "text-slate-500"}`}>{client.email}</p>
      </div>

      <div className="grid grid-cols-2 gap-2">
        <button
          type="button"
          className="rounded border border-orange-400/40 py-1.5 text-[10px] font-bold text-orange-400 transition-colors hover:bg-orange-500 hover:text-white"
        >
          Modifier
        </button>
        <button
          type="button"
          className="rounded border border-red-500/40 py-1.5 text-[10px] font-bold text-red-400 transition-colors hover:bg-red-500 hover:text-white"
        >
          Effacer
        </button>
      </div>
    </article>
  );
}

export default ClientCard;
