import { useEffect, useMemo, useState } from "react";

const inputClassName =
  "w-full rounded-lg border border-white/60 bg-white/80 px-3.5 py-2.5 text-sm text-slate-800 outline-none transition-all duration-200 placeholder:text-slate-400 focus:border-blue-400 focus:ring-2 focus:ring-blue-400/40 focus:bg-white disabled:cursor-not-allowed disabled:bg-white/50 disabled:text-slate-400 backdrop-blur-sm shadow-sm";
const labelClassName = "mb-1.5 block text-xs font-semibold uppercase tracking-wide text-white/90 drop-shadow-sm";

function AddTechnicienModal({ isOpen, clientName, clientMachines = [], onClose, onSubmit }) {
  const [form, setForm] = useState({
    lastName: "",
    firstName: "",
    email: "",
    location: "",
    machineIds: [],
  });

  useEffect(() => {
    if (!isOpen) return;
    const defaultMachineIds = clientMachines.slice(0, 1).map((machine) => machine.id);
    setForm((previous) => ({
      ...previous,
      machineIds: previous.machineIds.length ? previous.machineIds : defaultMachineIds,
    }));
  }, [isOpen, clientMachines]);

  const machineLabelById = useMemo(
    () => new Map(clientMachines.map((machine) => [machine.id, machine.name || machine.id])),
    [clientMachines]
  );

  if (!isOpen) return null;

  const handleChange = (field) => (event) => {
    setForm((previous) => ({ ...previous, [field]: event.target.value }));
  };

  const handleMachineToggle = (machineId) => {
    setForm((previous) => {
      const isSelected = previous.machineIds.includes(machineId);
      return {
        ...previous,
        machineIds: isSelected ? previous.machineIds.filter((id) => id !== machineId) : [...previous.machineIds, machineId],
      };
    });
  };

  const handleSubmit = (event) => {
    event.preventDefault();
    const hasEmail = Boolean(form.email.trim());
    const hasLastName = Boolean(form.lastName.trim());
    const hasFirstName = Boolean(form.firstName.trim());
    const hasMachine = form.machineIds.length > 0;
    if (!hasEmail) return;
    if (!hasLastName || !hasFirstName) return;
    if (!hasMachine) return;

    onSubmit({
      name: `${form.firstName.trim()} ${form.lastName.trim()}`.trim(),
      email: form.email.trim(),
      specialty: "Maintenance terrain",
      phone: "A completer",
      location: form.location.trim(),
      technicalDescription: "",
      machineIds: form.machineIds,
      requestMode: "manual",
    });
    setForm({
      lastName: "",
      firstName: "",
      email: "",
      location: "",
      machineIds: [],
    });
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-blue-950/30 p-4 backdrop-blur-md">
      <div className="w-full max-w-3xl rounded-2xl border border-white/30 bg-gradient-to-br from-blue-500/30 via-blue-400/20 to-cyan-400/20 p-6 shadow-2xl shadow-blue-900/30 backdrop-blur-xl transition-all duration-300 ease-out animate-in fade-in zoom-in-95 ring-1 ring-white/20">
        <div className="flex flex-wrap items-start justify-between gap-3 border-b border-white/30 pb-4">
          <div>
            <h3 className="text-xl font-semibold text-white drop-shadow-md">Demande d'ajout technicien</h3>
            <p className="mt-1 text-xs text-white/80">
              Client concerne: <span className="font-medium text-white">{clientName}</span>
            </p>
          </div>
          <span className="rounded-full border border-orange-200/60 bg-orange-400/30 px-3 py-1 text-[11px] font-semibold uppercase tracking-wide text-orange-50 backdrop-blur-sm shadow-sm">
            Workflow Conception
          </span>
        </div>

        <form className="mt-5 space-y-5" onSubmit={handleSubmit}>
          <div className="grid gap-4 md:grid-cols-2">
            <div>
              <label className={labelClassName}>Nom</label>
              <input
                className={inputClassName}
                value={form.lastName}
                onChange={handleChange("lastName")}
                type="text"
                required
                placeholder="Ex: Hemli"
              />
            </div>
            <div>
              <label className={labelClassName}>Prenom</label>
              <input
                className={inputClassName}
                value={form.firstName}
                onChange={handleChange("firstName")}
                type="text"
                required
                placeholder="Ex: Morad"
              />
            </div>
            <div>
              <label className={labelClassName}>Mail</label>
              <input
                className={inputClassName}
                value={form.email}
                onChange={handleChange("email")}
                type="email"
                required
                placeholder="Ex: technicien@entreprise.com"
              />
            </div>
            <div>
              <label className={labelClassName}>Localisation</label>
              <input className={inputClassName} value={form.location} onChange={handleChange("location")} type="text" placeholder="Ex: Sousse" />
            </div>
          </div>

          <div>
            <div className="mb-2 flex items-center justify-between">
              <label className={labelClassName}>Selection de machine</label>
              <span className="rounded-full border border-white/40 bg-white/20 px-2 py-0.5 text-[10px] font-semibold text-white backdrop-blur-sm">
                {form.machineIds.length} selection(s)
              </span>
            </div>
            <div className="max-h-44 space-y-2 overflow-auto rounded-xl border border-white/30 bg-white/15 p-3 backdrop-blur-md">
              {clientMachines.map((machine) => (
                <label
                  key={machine.id}
                  className="flex cursor-pointer items-center justify-between rounded-lg border border-transparent bg-white/40 px-2 py-1.5 text-xs text-slate-800 transition hover:border-white/60 hover:bg-white/60"
                >
                  <span className="flex min-w-0 items-center gap-2">
                    <input
                      type="checkbox"
                      checked={form.machineIds.includes(machine.id)}
                      onChange={() => handleMachineToggle(machine.id)}
                      className="h-4 w-4 accent-blue-600"
                    />
                    <span className="truncate font-medium">{machineLabelById.get(machine.id)}</span>
                  </span>
                  <span className="text-[11px] text-slate-600">{machine.id}</span>
                </label>
              ))}
              {!clientMachines.length && <p className="text-[12px] text-white/80">Aucune machine disponible pour ce client.</p>}
            </div>
            {form.machineIds.length === 0 && <p className="mt-1 text-[11px] text-red-200 drop-shadow-sm">Selectionnez au moins une machine.</p>}
          </div>

          <div className="flex items-center justify-end gap-3 border-t border-white/30 pt-4">
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg border border-white/40 bg-white/15 px-4 py-2 text-sm font-medium text-white transition-colors duration-200 hover:border-white/70 hover:bg-white/25 backdrop-blur-sm"
            >
              Annuler
            </button>
            <button
              type="submit"
              className="rounded-lg bg-orange-500 px-5 py-2 text-sm font-semibold text-white shadow-md shadow-orange-500/30 transition-colors duration-200 hover:bg-orange-400"
            >
              Envoyer la demande
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

export default AddTechnicienModal;
