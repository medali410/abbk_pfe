import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

# Configuration visuelle
plt.style.use('ggplot')
sns.set_theme(style="whitegrid")

def analyze_factory_data(csv_path):
    if not os.path.exists(csv_path):
        print(f"Erreur : Le fichier {csv_path} est introuvable.")
        return

    print(f"--- ANALYSE PRO DU DATASET : {csv_path} ---")
    
    # Chargement
    df = pd.read_csv(csv_path)
    
    # 1. Aperçu des colonnes
    print("\n✅ Colonnes détectées :")
    print(df.columns.tolist())
    
    # 2. Statistiques descriptives
    print("\n📈 Statistiques des paramètres physiques :")
    numeric_cols = ['Air temperature [K]', 'Process temperature [K]', 'Rotational speed [rpm]', 'Torque [Nm]', 'Tool wear [min]']
    print(df[numeric_cols].describe().round(2))
    
    # 3. Analyse des pannes
    print("\n❌ Analyse des types de pannes :")
    failure_cols = ['TWF', 'HDF', 'PWF', 'OSF', 'RNF']
    failures = df[failure_cols].sum()
    print(failures)

    # 4. Création de graphiques (Si matplotlib est dispo)
    try:
        plt.figure(figsize=(12, 6))
        
        # Plot 1: Distribution des températures
        plt.subplot(1, 2, 1)
        sns.histplot(df['Air temperature [K]'], color='skyblue', kde=True, label='Air Temp')
        sns.histplot(df['Process temperature [K]'], color='orange', kde=True, label='Process Temp')
        plt.title('Distribution des Températures (K)')
        plt.legend()

        # Plot 2: Répartition des Pannes
        plt.subplot(1, 2, 2)
        failures.plot(kind='bar', color='red', alpha=0.7)
        plt.title('Causes des Pannes Industrielles')
        plt.ylabel('Nombre de cas')
        
        output_plot = 'ai_analysis_overview.png'
        plt.tight_layout()
        plt.savefig(output_plot)
        print(f"\n📊 Graphique généré : {output_plot}")
        
    except Exception as e:
        print(f"\n⚠️ Impossible de générer le graphique : {e}")

    # 5. Conclusion pour Gemini
    print("\n🤖 PRÉPA POUR GEMINI IA :")
    correlation = df[numeric_cols + ['Machine failure']].corr()['Machine failure'].sort_values(ascending=False)
    print("Principales corrélations avec la panne :")
    print(correlation)

if __name__ == "__main__":
    # Utilisation du chemin absolu pour éviter les erreurs de dossier courant
    csv_absolute_path = r'C:\Users\ASUS\.gemini\antigravity\scratch\iot-backend\ai4i2020.csv'
    analyze_factory_data(csv_absolute_path)
