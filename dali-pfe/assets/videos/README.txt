Placez vos vidéos hero ici (MP4 H.264 recommandé).

Noms de fichiers : sans espaces ni parentheses (ex. machine_01.mp4).
  Mauvais : mon video (1).mp4
  Bon   : mon_video_1.mp4

Apres ajout ou remplacement de fichiers :
  1. Arreter Flutter (touche q dans le terminal)
  2. flutter pub get
  3. flutter run -d chrome --dart-define=API_PORT=3001
  (un simple hot reload R ne charge PAS les nouveaux assets)

Lecture en boucle sur la page d'accueil et le catalogue client.
