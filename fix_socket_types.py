import os

root_dir = r"C:\Users\ASUS\Documents\abbk_pfe\dali-pfe\lib"

count = 0
for subdir, dirs, files in os.walk(root_dir):
    for file in files:
        if file.endswith(".dart"):
            path = os.path.join(subdir, file)
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            if "'transports': ['websocket']" in content:
                new_content = content.replace("'transports': ['websocket']", "'transports': <String>['websocket']")
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(new_content)
                count += 1
                print(f"Fixed {file}")

print(f"Done fixing {count} files.")
