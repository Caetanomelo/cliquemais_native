// Eixo nativo x alvo (matriz completa). Os 3 idiomas sao simetricos agora --
// nenhum e mais "base/default" sobre os outros (substitui
// kCourseOverrideLanguages, que so cobria 'es' como excecao sobre um par
// en/pt implicito).
const List<String> kLanguages = ['en', 'es', 'pt'];
const Map<String, String> kLanguageLabels = {'en': 'Inglês', 'es': 'Espanhol', 'pt': 'Português'};
const Map<String, String> kLanguageLocale = {'en': 'en-US', 'es': 'es-US', 'pt': 'pt-BR'};

String resolveLocale(String language) => kLanguageLocale[language] ?? 'en-US';

// Espelha a constraint profiles_native_target_distinct (WEB_BASE migration
// 037): ninguem aprende o proprio idioma nativo.
bool isValidPair(String native, String target) =>
    native != target && kLanguages.contains(native) && kLanguages.contains(target);

// Espelha `legacyNative` em src/main.js (WEB_BASE) -- os 3 pares (target,
// native) que existiam antes de native_language existir como coluna: quem
// aprende pt sempre foi tratado como nativo de en; quem aprende en ou es
// sempre foi tratado como nativo de pt. Usado pra saber se um bloco de
// conteudo usa o shape antigo de overlay (sem sufixo) ou o shape novo
// (chave plana `${target}_${native}`).
String legacyNative(String target) => target == 'pt' ? 'en' : 'pt';
