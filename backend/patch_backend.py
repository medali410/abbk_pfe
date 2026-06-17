import codecs

def patch_file(path, target, replacement):
    with codecs.open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    content = content.replace(target, replacement)
    with codecs.open(path, 'w', encoding='utf-8') as f:
        f.write(content)

# Fix telemetryController.js
tc_path = r'C:\Users\ASUS\Documents\abbk_pfe\backend\src\controllers\telemetryController.js'
tc_target = '''            prisma.machine.findUnique({
                where: { id: machineId }
            })'''
tc_replacement = '''            prisma.machine.findFirst({
                where: machineId.length === 24 ? { id: machineId } : { name: machineId }
            })'''
patch_file(tc_path, tc_target, tc_replacement)

# Fix aiPredictionService.js
ai_path = r'C:\Users\ASUS\Documents\abbk_pfe\backend\src\lib\aiPredictionService.js'
ai_target1 = '''      const machine = await prisma.machine.findUnique({
        where: { id: String(machineId) }
      });'''
ai_replacement1 = '''      const machine = await prisma.machine.findFirst({
        where: machineId.length === 24 ? { id: String(machineId) } : { name: String(machineId) }
      });'''

ai_target2 = '''      const machine = await prisma.machine.findUnique({
        where: { id: machineId }
      });'''
ai_replacement2 = '''      const machine = await prisma.machine.findFirst({
        where: machineId.length === 24 ? { id: machineId } : { name: machineId }
      });'''

patch_file(ai_path, ai_target1, ai_replacement1)
patch_file(ai_path, ai_target2, ai_replacement2)

print("Backend patched")
