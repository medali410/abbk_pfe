const fs = require('fs');
const files = [
    'lib/widgets/chat/chat_sidebar.dart',
    'lib/widgets/chat/chat_main_area.dart',
    'lib/widgets/chat/chat_info_panel.dart',
    'lib/widgets/message_equipe_view.dart'
];
const props = [
    'bg', 'sidebar', 'header', 'panel', 'activeItem', 'myBubble', 'otherBubble',
    'text', 'muted', 'accent', 'online', 'offline', 'unread', 'roleAdmin',
    'roleConcepteur', 'roleTechnicien', 'roleMaintenance', 'roleClient',
    'titleStyle', 'subtitleStyle', 'nameStyle', 'messageStyle', 'timeStyle',
    'roleBadgeStyle', 'glassDecoration', 'inputDecoration'
];
files.forEach(f => {
    if (fs.existsSync(f)) {
        let content = fs.readFileSync(f, 'utf8');
        props.forEach(p => {
            const regex = new RegExp('ChatTheme\\.' + p + '(?![a-zA-Z0-9_])', 'g');
            content = content.replace(regex, 'ChatTheme.of(context).' + p);
        });
        fs.writeFileSync(f, content, 'utf8');
        console.log('Updated ' + f);
    }
});
