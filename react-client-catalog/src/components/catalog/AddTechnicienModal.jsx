import { useEffect, useMemo, useState } from "react";

const specialties = ["Terrain", "Electrique", "Mecanique", "Hydraulique"];

const inputClassName =
  "w-full rounded-lg border border-slate-700/90 bg-[#101426] px-3.5 py-2.5 text-sm text-slate-100 outline-none transition-all duration-200 placeholder:text-slate-500 focus:border-orange-400 focus:ring-2 focus:ring-orange-500/20 disabled:cursor-not-allowed disabled:bg-[#0E1220] disabled:text-slate-500";
const labelClassName = "mb-1.5 block text-xs font-semibold uppercase tracking-wide text-slate-300";

function AddTechnicienModal({ isOpen, clientName, clientMachines = [], onClose, onSubmit }) {
  const [form, setForm] = useState({
    name: "",
    email: "",
    specialty: specialties[0],
    phone: "",
    location: "",
    technicalDescription: "",
    machineIds: [],
    requestMode: "manual",
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
    const hasName = Boolean(form.name.trim());
    const hasPhone = Boolean(form.phone.trim());
    const hasMachine = form.machineIds.length > 0;
    const isGoogleMode = form.requestMode === "google";
    if (!hasEmail) return;
    if (!isGoogleMode && (!hasName || !hasPhone)) return;
    if (!hasMachine) return;

    onSubmit({
      name: isGoogleMode ? form.email.split("@")[0] : form.name.trim(),
      email: form.email.trim(),
      specialty: form.specialty,
      phone: isGoogleMode ? "A completer" : form.phone.trim(),
      location: form.location.trim(),
      technicalDescription: form.technicalDescription.trim(),
      machineIds: form.machineIds,
      requestMode: form.requestMode,
    });
    setForm({
      name: "",
      email: "",
      specialty: specialties[0],
      phone: "",
      location: "",
      technicalDescription: "",
      machineIds: [],
      requestMode: "manual",
    });
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm">
      <div className="w-full max-w-3xl rounded-2xl border border-slate-700/80 bg-[#171B2A] p-6 opacity-100 shadow-2xl shadow-black/30 transition-all duration-300 ease-out animate-in fade-in zoom-in-95">
        <div className="flex flex-wrap items-start justify-between gap-3 border-b border-slate-700/70 pb-4">
          <div>
            <h3 className="text-xl font-semibold text-slate-100">Demande d'ajout technicien</h3>
            <p className="mt-1 text-xs text-slate-400">
              Client concerne: <span className="font-medium text-slate-200">{clientName}</span>
            </p>
          </div>
          <span className="rounded-full border border-orange-400/40 bg-orange-500/10 px-3 py-1 text-[11px] font-semibold uppercase tracking-wide text-orange-300">
            Workflow Conception
          </span>
        </div>

        <form className="mt-5 space-y-5" onSubmit={handleSubmit}>
          <div className="rounded-xl border border-slate-700/70 bg-[#11162A] p-4">
            <label className={labelClassName}>Type de demande</label>
            <select className={inputClassName} value={form.requestMode} onChange={handleChange("requestMode")}>
              <option value="manual">Saisie complete technicien</option>
              <option value="google">Creer avec Google Mail</option>
            </select>
            <p className="mt-2 text-xs text-slate-400">
              {form.requestMode === "google"
                ? "Le nom et le telephone seront completes apres la validation."
                : "Tous les champs principaux sont saisis manuellement."}
            </p>
          </div>

          <div className="grid gap-4 md:grid-cols-2">
            <div>
              <label className={labelClassName}>Nom complet</label>
              <input
                className={inputClassName}
                value={form.name}
                onChange={handleChange("name")}
                type="text"
                required={form.requestMode !== "google"}
                disabled={form.requestMode === "google"}
                placeholder={form.requestMode === "google" ? "Genere depuis Google Mail" : "Ex: Morad Hemli"}
              />
            </div>
            <div>
              <label className={labelClassName}>{form.requestMode === "google" ? "Google Mail" : "Email professionnel"}</label>
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
              <label className={labelClassName}>Specialite</label>
              <select className={inputClassName} value={form.specialty} onChange={handleChange("specialty")}>
                {specialties.map((specialty) => (
                  <option key={specialty} value={specialty}>
                    {specialty}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className={labelClassName}>Telephone</label>
              <input
                className={inputClassName}
                value={form.phone}
                onChange={handleChange("phone")}
                type="text"
                required={form.requestMode !== "google"}
                disabled={form.requestMode === "google"}
                placeholder={form.requestMode === "google" ? "A completer apres validation" : "Ex: +216 12 345 678"}
              />
            </div>
            <div className="md:col-span-2">
              <label className={labelClassName}>Localisation</label>
              <input className={inputClassName} value={form.location} onChange={handleChange("location")} type="text" placeholder="Ex: Sousse, Tunisie" />
            </div>
          </div>

          <div>
            <label className={labelClassName}>Description technique</label>
            <textarea
              className={`${inputClassName} min-h-[96px] resize-y`}
              value={form.technicalDescription}
              onChange={handleChange("technicalDescription")}
              placeholder="Resume des competences, certifications et perimetre d'intervention."
            />
          </div>

          <div>
            <div className="mb-2 flex items-center justify-between">
              <label className={labelClassName}>Machines a controler</label>
              <span className="rounded-full border border-slate-600 px-2 py-0.5 text-[10px] font-semibold text-slate-300">
                {form.machineIds.length} selection(s)
              </span>
            </div>
            <div className="max-h-44 space-y-2 overflow-auto rounded-xl border border-slate-700 bg-[#0F1117] p-3">
              {clientMachines.map((machine) => (
                <label
                  key={machine.id}
                  className="flex cursor-pointer items-center justify-between rounded-lg border border-transparent px-2 py-1.5 text-xs text-slate-200 transition hover:border-slate-600 hover:bg-[#171D30]"
                >
                  <span className="flex min-w-0 items-center gap-2">
                  <input
                    type="checkbox"
                    checked={form.machineIds.includes(machine.id)}
                    onChange={() => handleMachineToggle(machine.id)}
                    className="h-4 w-4 accent-orange-500"
                  />
                    <span className="truncate">{machineLabelById.get(machine.id)}</span>
                  </span>
                  <span className="text-[11px] text-slate-500">{machine.id}</span>
                </label>
              ))}
              {!clientMachines.length && <p className="text-[12px] text-slate-400">Aucune machine disponible pour ce client.</p>}
            </div>
            {form.machineIds.length === 0 && <p className="mt-1 text-[11px] text-red-400">Selectionnez au moins une machine.</p>}
          </div>

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
              Envoyer la demande
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

export default AddTechnicienModal;
