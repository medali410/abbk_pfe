import { useState } from "react";

const agentTypes = ["Preventif", "Correctif", "Urgence"];

const inputClassName =
  "w-full rounded-lg border border-slate-700/90 bg-[#101426] px-3.5 py-2.5 text-sm text-slate-100 outline-none transition-all duration-200 placeholder:text-slate-500 focus:border-orange-400 focus:ring-2 focus:ring-orange-500/20";
const labelClassName = "mb-1.5 block text-xs font-semibold uppercase tracking-wide text-slate-300";

function AddMaintenanceModal({ isOpen, clientName, onClose, onSubmit }) {
  const [form, setForm] = useState({
    name: "",
    email: "",
    agentType: agentTypes[0],
    available: true,
  });

  if (!isOpen) return null;

  const handleChange = (field) => (event) => {
    const value = field === "available" ? event.target.checked : event.target.value;
    setForm((previous) => ({ ...previous, [field]: value }));
  };

  const handleSubmit = (event) => {
    event.preventDefault();
    if (!form.name.trim() || !form.email.trim()) return;
    onSubmit({
      name: form.name.trim(),
      email: form.email.trim(),
      agentType: form.agentType,
      available: form.available,
    });
    setForm({ name: "", email: "", agentType: agentTypes[0], available: true });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm">
      <div className="w-full max-w-2xl rounded-2xl border border-slate-700/80 bg-[#171B2A] p-6 opacity-100 shadow-2xl shadow-black/30 transition-all duration-300 ease-out">
        <div className="flex flex-wrap items-start justify-between gap-3 border-b border-slate-700/70 pb-4">
          <div>
            <h3 className="text-xl font-semibold text-slate-100">Ajout d&apos;agent maintenance</h3>
            <p className="mt-1 text-xs text-slate-400">
              Client concerne: <span className="font-medium text-slate-200">{clientName}</span>
            </p>
          </div>
          <span className="rounded-full border border-orange-400/40 bg-orange-500/10 px-3 py-1 text-[11px] font-semibold uppercase tracking-wide text-orange-300">
            Equipe Maintenance
          </span>
        </div>

        <form className="mt-5 space-y-5" onSubmit={handleSubmit}>
          <div className="grid gap-4 md:grid-cols-2">
            <div>
              <label className={labelClassName}>Nom complet</label>
              <input className={inputClassName} value={form.name} onChange={handleChange("name")} type="text" placeholder="Ex: Ahmed Ben Ali" required />
            </div>
            <div>
              <label className={labelClassName}>Email professionnel</label>
              <input
                className={inputClassName}
                value={form.email}
                onChange={handleChange("email")}
                type="email"
                placeholder="Ex: agent@entreprise.com"
                required
              />
            </div>
            <div className="md:col-span-2">
              <label className={labelClassName}>Type d&apos;agent</label>
              <select className={inputClassName} value={form.agentType} onChange={handleChange("agentType")}>
                {agentTypes.map((agentType) => (
                  <option key={agentType} value={agentType}>
                    {agentType}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <label className="flex items-center justify-between rounded-xl border border-slate-700 bg-[#101426] px-4 py-3">
            <span className="text-sm font-medium text-slate-200">Disponibilite</span>
            <span className="inline-flex items-center gap-2">
              <input
                type="checkbox"
                checked={form.available}
                onChange={handleChange("available")}
                className="h-4 w-4 rounded border-slate-500 bg-slate-900 text-orange-500 focus:ring-orange-500"
              />
              <span
                className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${
                  form.available ? "bg-emerald-500/15 text-emerald-300" : "bg-red-500/15 text-red-300"
                }`}
              >
                {form.available ? "Disponible" : "Indisponible"}
              </span>
            </span>
          </label>

          <div className="flex items-center justify-end gap-3 border-t border-slate-700/70 pt-4">
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg border border-slate-600 px-4 py-2 text-sm font-medium text-slate-200 transition-colors duration-200 hover:border-slate-400"
            >
              Annuler
            </button>
            <button
              type="submit"
              className="rounded-lg bg-orange-500 px-5 py-2 text-sm font-semibold text-[#101426] transition-colors duration-200 hover:bg-orange-400"
            >
              Enregistrer agent
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

export default AddMaintenanceModal;
