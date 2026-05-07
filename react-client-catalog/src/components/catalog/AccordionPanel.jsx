import { Settings, SlidersHorizontal, UserPlus, Wrench } from "lucide-react";
import MaintenanceCard from "./MaintenanceCard";
import MachineRow from "./MachineRow";
import TechnicienCard from "./TechnicienCard";

function AccordionPanel({
  client,
  isOpen,
  onAddMaintenance,
  onAddTechnicienRequest,
  onApproveTechnicienRequest,
  onRejectTechnicienRequest,
}) {
  const pendingRequests = client.technicienRequests ?? [];
  const rejectedRequests = client.rejectedTechnicienRequests ?? [];

  return (
    <section
      className={`overflow-hidden transition-all duration-300 ease-in-out ${
        isOpen ? "max-h-[1200px]" : "max-h-0"
      }`}
    >
      <div className="space-y-8">
        <div className="grid grid-cols-1 gap-8 xl:grid-cols-2">
          <div className="space-y-4">
            <header className="flex items-center justify-between gap-2">
              <div className="inline-flex items-center gap-2 text-orange-400">
                <SlidersHorizontal size={18} />
                <h4 className="text-xs font-bold uppercase tracking-widest text-white">Techniciens</h4>
              </div>
              <button
                type="button"
                onClick={onAddTechnicienRequest}
                className="inline-flex items-center gap-1 rounded bg-orange-500 px-3 py-1.5 text-[10px] font-bold uppercase text-[#0A0A0F] transition-colors hover:bg-orange-400"
              >
                <UserPlus size={12} />
                Demande de add technicien
              </button>
            </header>
            {pendingRequests.length > 0 && (
              <div className="rounded-lg border border-orange-500/30 bg-[#171722] p-3">
                <p className="mb-2 text-[10px] font-bold uppercase tracking-wide text-orange-300">
                  Demandes en attente - validation concepteur
                </p>
                <div className="space-y-2">
                  {pendingRequests.map((request) => (
                    <div
                      key={request.id}
                      className="flex flex-col gap-2 rounded border border-[#2D2D41] bg-[#131322] p-2 text-[11px] text-slate-300 md:flex-row md:items-center md:justify-between"
                    >
                      <div className="min-w-0">
                        <p className="truncate font-semibold text-white">{request.name}</p>
                        <p className="truncate text-slate-400">
                          {request.email} - {request.source}
                        </p>
                      </div>
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => onApproveTechnicienRequest(client.id, request.id)}
                          className="rounded border border-green-500/40 bg-green-500/10 px-3 py-1 text-[10px] font-bold uppercase text-green-300 transition hover:bg-green-500/20"
                        >
                          Valider
                        </button>
                        <button
                          type="button"
                          onClick={() => {
                            const reason = window.prompt("Motif du refus de la demande technicien:");
                            if (!reason || !reason.trim()) return;
                            onRejectTechnicienRequest(client.id, request.id, reason.trim());
                          }}
                          className="rounded border border-red-500/40 bg-red-500/10 px-3 py-1 text-[10px] font-bold uppercase text-red-300 transition hover:bg-red-500/20"
                        >
                          Refuser
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
            {rejectedRequests.length > 0 && (
              <div className="rounded-lg border border-red-500/20 bg-[#19141C] p-3">
                <p className="mb-2 text-[10px] font-bold uppercase tracking-wide text-red-300">
                  Demandes refusees
                </p>
                <div className="space-y-2">
                  {rejectedRequests.map((request) => (
                    <div key={request.id} className="rounded border border-[#3A2530] bg-[#1B1521] p-2 text-[11px]">
                      <p className="font-semibold text-white">{request.name}</p>
                      <p className="text-slate-400">{request.email}</p>
                      <p className="text-red-300">Motif: {request.rejectReason}</p>
                    </div>
                  ))}
                </div>
              </div>
            )}
            <div className="grid grid-cols-1 gap-3">
              {client.techniciens.map((technicien) => (
                <TechnicienCard key={technicien.id} technicien={technicien} />
              ))}
            </div>
          </div>

          <div className="space-y-4">
            <header className="flex items-center justify-between gap-2">
              <div className="inline-flex items-center gap-2 text-orange-400">
                <Settings size={18} />
                <h4 className="text-xs font-bold uppercase tracking-widest text-white">Agents maintenance</h4>
              </div>
              <button
                type="button"
                onClick={onAddMaintenance}
                className="inline-flex items-center gap-1 rounded bg-orange-500 px-3 py-1.5 text-[10px] font-bold uppercase text-[#0A0A0F] transition-colors hover:bg-orange-400"
              >
                <Wrench size={12} />
                Add Maintenance
              </button>
            </header>
            <div className="grid grid-cols-1 gap-3">
              {client.maintenanceAgents.map((agent) => (
                <MaintenanceCard key={agent.id} agent={agent} />
              ))}
            </div>
          </div>
        </div>

        <div className="space-y-4">
          <header className="mb-4 inline-flex items-center gap-2 text-orange-400">
            <Wrench size={18} />
            <h4 className="text-xs font-bold uppercase tracking-widest text-white">Machines</h4>
            <span className="ml-2 text-[10px] italic normal-case text-slate-500">Pour {client.name}</span>
          </header>
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
            {client.machines.map((machine) => (
              <MachineRow key={machine.id} machine={machine} />
            ))}
            {!client.machines.length && (
              <div className="rounded-xl border border-[#222233] bg-[#14141F] p-4 text-xs text-slate-500">
                Aucune machine enregistree pour ce client.
              </div>
            )}
          </div>
        </div>
      </div>
    </section>
  );
}

export default AccordionPanel;
