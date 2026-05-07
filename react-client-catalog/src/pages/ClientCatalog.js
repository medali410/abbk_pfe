import { useEffect, useMemo, useState } from "react";
import { Bell, BookOpen, Briefcase, LogOut, Search } from "lucide-react";
import AccordionPanel from "../components/catalog/AccordionPanel";
import AddMaintenanceModal from "../components/catalog/AddMaintenanceModal";
import AddTechnicienModal from "../components/catalog/AddTechnicienModal";
import { clients as mockClients } from "../data/mockClientCatalogData";

const API_BASE_URL = "http://127.0.0.1:3001/api";
const AUTH_TOKEN_KEYS = ["api_auth_token", "token", "authToken"];

const getAuthToken = () => {
  if (typeof window === "undefined") return "";
  for (const key of AUTH_TOKEN_KEYS) {
    const token = window.localStorage.getItem(key);
    if (token) return token;
  }
  return "";
};

const buildHeaders = (withAuth = false) => {
  const headers = { "Content-Type": "application/json" };
  if (!withAuth) return headers;
  const token = getAuthToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  return headers;
};

function ClientCatalog() {
  const [clients, setClients] = useState(mockClients);
  const [selectedClientId, setSelectedClientId] = useState(mockClients[0]?.id ?? null);
  const [clientSearch, setClientSearch] = useState("");
  const [detailSearch, setDetailSearch] = useState("");
  const [technicienModalClientId, setTechnicienModalClientId] = useState(null);
  const [maintenanceModalClientId, setMaintenanceModalClientId] = useState(null);

  const activeTechnicienClient = useMemo(
    () => clients.find((client) => client.id === technicienModalClientId) ?? null,
    [clients, technicienModalClientId]
  );
  const activeMaintenanceClient = useMemo(
    () => clients.find((client) => client.id === maintenanceModalClientId) ?? null,
    [clients, maintenanceModalClientId]
  );

  const filteredClients = useMemo(() => {
    return clients.filter((client) => {
      const key = clientSearch.toLowerCase().trim();
      if (!key) return true;
      return client.name.toLowerCase().includes(key) || client.email.toLowerCase().includes(key) || client.id.toLowerCase().includes(key);
    });
  }, [clients, clientSearch]);
  const selectedClient = useMemo(
    () => filteredClients.find((client) => client.id === selectedClientId) ?? filteredClients[0] ?? null,
    [filteredClients, selectedClientId]
  );
  const detailFilteredClient = useMemo(() => {
    if (!selectedClient) return null;
    const key = detailSearch.toLowerCase().trim();
    if (!key) return selectedClient;

    return {
      ...selectedClient,
      techniciens: selectedClient.techniciens.filter(
        (item) => item.name.toLowerCase().includes(key) || item.id.toLowerCase().includes(key) || item.email.toLowerCase().includes(key)
      ),
      maintenanceAgents: selectedClient.maintenanceAgents.filter(
        (item) => item.name.toLowerCase().includes(key) || item.id.toLowerCase().includes(key) || item.email.toLowerCase().includes(key)
      ),
      machines: selectedClient.machines.filter((item) => item.name.toLowerCase().includes(key) || item.id.toLowerCase().includes(key)),
    };
  }, [selectedClient, detailSearch]);

  useEffect(() => {
    if (!selectedClient && selectedClientId !== null) {
      setSelectedClientId(null);
      return;
    }
    if (selectedClient && selectedClient.id !== selectedClientId) {
      setSelectedClientId(selectedClient.id);
    }
  }, [selectedClient, selectedClientId]);

  useEffect(() => {
    const hydratePendingRequests = async () => {
      const token = getAuthToken();
      if (!token) return;
      try {
        const response = await fetch(`${API_BASE_URL}/purchase-requests?status=PENDING`, {
          method: "GET",
          headers: buildHeaders(true),
        });
        if (!response.ok) return;
        const pending = await response.json();
        const byClientId = pending.reduce((accumulator, item) => {
          if (!item?.linkedClientId) return accumulator;
          const request = {
            id: item.id ?? item._id,
            name: item.requesterName ?? "Client",
            email: item.requesterEmail ?? "",
            specialty: "Maintenance terrain",
            phone: item.requesterPhone ?? "",
            source: item.requestType === "TECHNICIAN_ADD" ? "Demande client (DB)" : "Achat machine",
            status: "pending",
          };
          if (!accumulator[item.linkedClientId]) accumulator[item.linkedClientId] = [];
          accumulator[item.linkedClientId].push(request);
          return accumulator;
        }, {});

        setClients((previous) =>
          previous.map((client) => ({
            ...client,
            technicienRequests: byClientId[client.id] ?? client.technicienRequests ?? [],
          }))
        );
      } catch (error) {
        console.error("Hydratation des demandes technicien impossible:", error);
      }
    };
    hydratePendingRequests();
  }, []);

  const handleAddTechnicien = async (payload) => {
    if (!technicienModalClientId) return;
    const randomCode = Array.from({ length: 8 }, () => Math.floor(Math.random() * 10)).join("");
    const tempRequestId = `REQ-TECH-${randomCode}`;
    const request = {
      id: tempRequestId,
      name: payload.name,
      email: payload.email,
      specialty: payload.specialty,
      phone: payload.phone,
      source: payload.requestMode === "google" ? "Google Mail" : "Saisie manuelle",
      status: "pending",
    };

    setClients((previous) =>
      previous.map((client) =>
        client.id === technicienModalClientId
          ? {
              ...client,
              technicienRequests: [...(client.technicienRequests ?? []), request],
            }
          : client
      )
    );

    try {
      const selectedMachineId = payload.machineIds?.[0];
      if (!selectedMachineId) throw new Error("Aucune machine selectionnee.");

      const machinesResponse = await fetch(`${API_BASE_URL}/machines`, {
        method: "GET",
      });
      if (!machinesResponse.ok) throw new Error("Chargement des machines impossible.");
      const apiMachines = await machinesResponse.json();
      const resolvedMachine = apiMachines.find((machine) => {
        const mongoId = String(machine.id ?? machine._id ?? "");
        const businessId = String(machine.machineId ?? machine.idBusiness ?? "");
        return selectedMachineId === mongoId || selectedMachineId === businessId;
      });
      if (!resolvedMachine) throw new Error("Machine introuvable en base.");

      const createResponse = await fetch(`${API_BASE_URL}/purchase-requests`, {
        method: "POST",
        headers: buildHeaders(),
        body: JSON.stringify({
          machineId: String(resolvedMachine.id ?? resolvedMachine._id),
          requesterName: payload.name,
          requesterEmail: payload.email,
          requesterPhone: payload.phone,
          location: payload.location ?? "",
          note: payload.technicalDescription ?? "",
          linkedClientId: technicienModalClientId,
          requestType: "TECHNICIAN_ADD",
          requestedSpecialty: payload.specialty ?? "",
          requestedMachineIds: payload.machineIds ?? [],
        }),
      });
      if (!createResponse.ok) {
        const errorText = await createResponse.text();
        throw new Error(errorText || "Creation de demande technicien refusee.");
      }
      const createdRequest = await createResponse.json();
      if (createdRequest?.id) {
        setClients((previous) =>
          previous.map((client) => {
            if (client.id !== technicienModalClientId) return client;
            return {
              ...client,
              technicienRequests: (client.technicienRequests ?? []).map((item) =>
                item.id === tempRequestId ? { ...item, id: createdRequest.id, source: "Demande client (DB)" } : item
              ),
            };
          })
        );
      }
    } catch (error) {
      console.error("Enregistrement DB demande technicien impossible:", error);
    }
    setTechnicienModalClientId(null);
  };

  const handleApproveTechnicienRequest = async (clientId, requestId) => {
    try {
      const token = getAuthToken();
      if (token && !String(requestId).startsWith("REQ-TECH-")) {
        await fetch(`${API_BASE_URL}/purchase-requests/${requestId}/status`, {
          method: "PATCH",
          headers: buildHeaders(true),
          body: JSON.stringify({ status: "VALIDATED", reviewedByName: "Concepteur" }),
        });
      }
    } catch (error) {
      console.error("Validation DB demande technicien impossible:", error);
    }
    setClients((previous) =>
      previous.map((client) => {
        if (client.id !== clientId) return client;
        const requests = client.technicienRequests ?? [];
        const approvedRequest = requests.find((item) => item.id === requestId);
        if (!approvedRequest) return client;

        const randomCode = String(Math.floor(100000 + Math.random() * 900000));
        const technicien = {
          id: `TECH-2026-${randomCode}`,
          name: approvedRequest.name,
          email: approvedRequest.email,
          specialty: approvedRequest.specialty,
          phone: approvedRequest.phone,
        };

        return {
          ...client,
          techniciens: [...client.techniciens, technicien],
          technicienRequests: requests.filter((item) => item.id !== requestId),
        };
      })
    );
  };

  const handleRejectTechnicienRequest = async (clientId, requestId, reason) => {
    try {
      const token = getAuthToken();
      if (token && !String(requestId).startsWith("REQ-TECH-")) {
        await fetch(`${API_BASE_URL}/purchase-requests/${requestId}/status`, {
          method: "PATCH",
          headers: buildHeaders(true),
          body: JSON.stringify({ status: "REJECTED", reviewedByName: "Concepteur" }),
        });
      }
    } catch (error) {
      console.error("Refus DB demande technicien impossible:", error);
    }
    setClients((previous) =>
      previous.map((client) => {
        if (client.id !== clientId) return client;
        const requests = client.technicienRequests ?? [];
        const rejectedRequest = requests.find((item) => item.id === requestId);
        if (!rejectedRequest) return client;

        return {
          ...client,
          technicienRequests: requests.filter((item) => item.id !== requestId),
          rejectedTechnicienRequests: [
            ...(client.rejectedTechnicienRequests ?? []),
            {
              ...rejectedRequest,
              status: "rejected",
              rejectReason: reason,
            },
          ],
        };
      })
    );
  };

  const handleAddMaintenance = (payload) => {
    if (!maintenanceModalClientId) return;
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const randomChunk = Array.from({ length: 8 }, () => chars[Math.floor(Math.random() * chars.length)]).join("");
    const agent = {
      id: `MAINT-${randomChunk}`,
      name: payload.name,
      email: payload.email,
      agentType: payload.agentType,
      available: payload.available,
    };

    setClients((previous) =>
      previous.map((client) =>
        client.id === maintenanceModalClientId
          ? { ...client, maintenanceAgents: [...client.maintenanceAgents, agent] }
          : client
      )
    );
    setMaintenanceModalClientId(null);
  };

  const getInitials = (name) =>
    name
      .split(" ")
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0]?.toUpperCase() ?? "")
      .join("");

  return (
    <main className="relative min-h-screen overflow-hidden bg-gradient-to-br from-blue-50 via-sky-100 to-blue-200 text-slate-800">
      <div className="pointer-events-none absolute -left-40 -top-40 h-96 w-96 rounded-full bg-blue-400/30 blur-3xl" aria-hidden="true" />
      <div className="pointer-events-none absolute -right-32 top-1/3 h-[28rem] w-[28rem] rounded-full bg-sky-300/30 blur-3xl" aria-hidden="true" />
      <div className="pointer-events-none absolute bottom-0 left-1/3 h-80 w-80 rounded-full bg-cyan-300/30 blur-3xl" aria-hidden="true" />

      <header className="sticky top-0 z-50 flex items-center justify-between border-b border-blue-200/60 bg-white/40 px-6 py-3 backdrop-blur-xl">
        <div className="flex items-center gap-8">
          <div className="flex flex-col">
            <h1 className="text-xl font-bold tracking-wider text-blue-950">KINETIC</h1>
            <span className="text-[10px] font-bold uppercase tracking-widest text-orange-500">Predictive Intelligence</span>
          </div>
        </div>
        <div className="flex items-center gap-4">
          <div className="hidden items-center gap-3 border-r border-blue-200/60 pr-4 sm:flex">
            <div className="flex h-10 w-10 items-center justify-center rounded-full border-2 border-orange-400/60 bg-white/70 text-xs font-bold text-orange-500 shadow-sm">
              ED
            </div>
            <div>
              <p className="text-xs font-bold uppercase text-blue-950">Equipe Design</p>
              <p className="text-[10px] text-blue-700/70">CONCEPTION</p>
            </div>
          </div>
          <button type="button" className="relative text-blue-700/70 transition hover:text-blue-950" aria-label="Notifications">
            <Bell size={22} />
            <span className="absolute right-0 top-0 h-2 w-2 rounded-full bg-orange-500" />
          </button>
          <button type="button" className="text-blue-700/70 transition hover:text-orange-500" aria-label="Deconnexion">
            <LogOut size={22} />
          </button>
        </div>
      </header>

      <div className="relative border-b border-blue-200/60 bg-white/30 px-6 py-4 backdrop-blur-xl">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div className="flex min-w-[300px] flex-1 items-center gap-6">
            <div className="relative w-full max-w-md">
              <Search size={16} className="pointer-events-none absolute left-3 top-2.5 text-blue-400" />
              <input
                value={clientSearch}
                onChange={(event) => setClientSearch(event.target.value)}
                className="w-full rounded-lg border border-blue-200/70 bg-white/70 py-2.5 pl-10 pr-4 text-sm text-slate-800 outline-none placeholder:text-slate-400 focus:border-blue-500 focus:ring-2 focus:ring-blue-400/30 backdrop-blur-sm"
                placeholder="Rechercher une machine..."
              />
            </div>
            <p className="hidden text-[10px] font-bold uppercase tracking-widest text-blue-700/70 md:block">Industrial Intelligence</p>
          </div>
          <div className="flex items-center gap-3">
            <button
              type="button"
              className="inline-flex items-center gap-2 rounded-lg bg-orange-500 px-5 py-2.5 text-xs font-bold text-white shadow-lg shadow-orange-500/30 transition hover:bg-orange-600"
            >
              <Briefcase size={14} />
              Ajouter une machine
            </button>
            <button
              type="button"
              className="rounded-lg border border-blue-300/70 bg-white/60 px-5 py-2.5 text-xs font-bold text-blue-900 transition hover:bg-white/90 backdrop-blur-sm"
            >
              Rafraichir
            </button>
          </div>
        </div>
      </div>

      <section className="relative flex min-h-[calc(100vh-145px)] flex-col md:flex-row">
        <aside className="flex w-full flex-col border-r border-blue-200/60 bg-white/30 backdrop-blur-xl md:w-80 lg:w-96">
          <div className="border-b border-blue-200/60 p-6">
            <div className="mb-1 flex items-center gap-3 text-orange-500">
              <BookOpen size={20} />
              <h2 className="text-lg font-bold tracking-tight text-blue-950">Client Catalog</h2>
            </div>
          </div>
          <div className="flex-1 space-y-3 overflow-y-auto p-4">
            {filteredClients.map((client) => {
              const isSelected = selectedClient?.id === client.id;
              const initials = getInitials(client.name);
              const hasAvatar = Boolean(client.avatarUrl);
              return (
                <div
                  key={client.id}
                  onClick={() => setSelectedClientId(client.id)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter" || event.key === " ") {
                      event.preventDefault();
                      setSelectedClientId(client.id);
                    }
                  }}
                  role="button"
                  tabIndex={0}
                  className={`w-full cursor-pointer rounded-xl border p-4 text-left transition-all duration-200 backdrop-blur-sm ${
                    isSelected
                      ? "border-orange-400/70 bg-white/80 ring-2 ring-orange-400/40 shadow-md shadow-orange-200/40"
                      : "border-blue-200/60 bg-white/50 hover:border-orange-400/60 hover:bg-white/70"
                  }`}
                >
                  <div className="flex items-start gap-3">
                    {hasAvatar ? (
                      <img
                        src={client.avatarUrl}
                        alt={`Avatar de ${client.name}`}
                        className={`h-12 w-12 shrink-0 rounded-full object-cover ${
                          isSelected ? "border-2 border-orange-400" : "border border-blue-200"
                        }`}
                        loading="lazy"
                      />
                    ) : (
                      <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full border border-blue-200 bg-blue-100/70 text-xs font-bold text-orange-500">
                        {initials || "CL"}
                      </div>
                    )}
                    <div className="min-w-0 flex-1">
                      <p className={`truncate text-sm font-bold ${isSelected ? "text-orange-600" : "text-blue-950"}`}>{client.name}</p>
                      <p className="truncate text-[10px] uppercase tracking-wide text-blue-700/70">{client.id}</p>
                      <p className="mt-1 truncate text-xs text-slate-700">{client.email}</p>
                    </div>
                  </div>
                  <div className="mt-3 grid grid-cols-3 gap-2 text-center">
                    <div className="rounded-lg border border-blue-200/60 bg-blue-50/60 px-2 py-1.5">
                      <p className="text-[10px] uppercase text-blue-700/70">Machines</p>
                      <p className="text-xs font-semibold text-blue-950">{client.machines.length}</p>
                    </div>
                    <div className="rounded-lg border border-blue-200/60 bg-blue-50/60 px-2 py-1.5">
                      <p className="text-[10px] uppercase text-blue-700/70">Techniciens</p>
                      <p className="text-xs font-semibold text-blue-950">{client.techniciens.length}</p>
                    </div>
                    <div className="rounded-lg border border-blue-200/60 bg-blue-50/60 px-2 py-1.5">
                      <p className="text-[10px] uppercase text-blue-700/70">Maintenance</p>
                      <p className="text-xs font-semibold text-blue-950">{client.maintenanceAgents.length}</p>
                    </div>
                  </div>
                </div>
              );
            })}
            {!filteredClients.length && (
              <div className="rounded-xl border border-blue-200/60 bg-white/50 p-4 text-xs text-blue-800/70 backdrop-blur-sm">
                Aucun client ne correspond a votre recherche.
              </div>
            )}
          </div>
        </aside>

        <section className="flex-1 overflow-y-auto p-6 md:p-8">
          <div className="mb-4 flex flex-col gap-3 md:flex-row md:items-center md:justify-end">
            <div className="relative w-full md:w-80">
              <Search size={14} className="pointer-events-none absolute left-3 top-2.5 text-blue-400" />
              <input
                value={detailSearch}
                onChange={(event) => setDetailSearch(event.target.value)}
                className="w-full rounded-lg border border-blue-200/70 bg-white/60 py-2 pl-10 pr-4 text-sm text-slate-800 outline-none placeholder:text-slate-400 focus:border-blue-500 focus:ring-2 focus:ring-blue-400/30 backdrop-blur-sm"
                placeholder="Rechercher par nom, ID ou email..."
              />
            </div>
          </div>
          {detailFilteredClient ? (
            <AccordionPanel
              client={detailFilteredClient}
              isOpen
              onAddTechnicienRequest={() => {
                setTechnicienModalClientId(detailFilteredClient.id);
              }}
              onApproveTechnicienRequest={handleApproveTechnicienRequest}
              onRejectTechnicienRequest={handleRejectTechnicienRequest}
              onAddMaintenance={() => {
                setMaintenanceModalClientId(detailFilteredClient.id);
              }}
            />
          ) : (
            <div className="rounded-xl border border-blue-200/60 bg-white/50 p-4 text-xs text-blue-800/70 backdrop-blur-sm">
              Selectionnez un client pour afficher son profil.
            </div>
          )}
        </section>
      </section>

      <footer className="relative flex items-center justify-between border-t border-blue-200/60 bg-white/40 px-6 py-3 text-[10px] text-blue-800/70 backdrop-blur-xl">
        <div>&copy; 2024 Kinetic Predictive Intelligence. All rights reserved.</div>
        <div className="hidden items-center gap-4 md:flex">
          <a className="transition hover:text-orange-500" href="#status">
            Status Systeme: <span className="text-green-600">Operationnel</span>
          </a>
          <a className="transition hover:text-orange-500" href="#privacy">
            Privacy Policy
          </a>
          <a className="transition hover:text-orange-500" href="#support">
            Contact Support
          </a>
        </div>
      </footer>

      <AddTechnicienModal
        isOpen={Boolean(technicienModalClientId)}
        clientName={activeTechnicienClient?.name ?? "-"}
        clientMachines={activeTechnicienClient?.machines ?? []}
        onClose={() => setTechnicienModalClientId(null)}
        onSubmit={handleAddTechnicien}
      />
      <AddMaintenanceModal
        isOpen={Boolean(maintenanceModalClientId)}
        clientName={activeMaintenanceClient?.name ?? "-"}
        onClose={() => setMaintenanceModalClientId(null)}
        onSubmit={handleAddMaintenance}
      />
    </main>
  );
}

export default ClientCatalog;
