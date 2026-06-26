/*
 * Minimal cross-platform @ohos.hilog JS shim for arkui-x mac.
 * Provides the logging surface used by app code (Logger.ets etc.).
 */
function format(args) {
    try {
        return Array.prototype.slice.call(args).map(function (a) {
            return (typeof a === 'object') ? JSON.stringify(a) : String(a);
        }).join(' ');
    } catch (e) {
        return '';
    }
}
const hilog = {
    LogLevel: { DEBUG: 3, INFO: 4, WARN: 5, ERROR: 6, FATAL: 7 },
    isLoggable: function (domain, tag, level) { return true; },
    debug: function (domain, tag) { console.log('[D]', tag, format(arguments)); },
    info: function (domain, tag) { console.log('[I]', tag, format(arguments)); },
    warn: function (domain, tag) { console.log('[W]', tag, format(arguments)); },
    error: function (domain, tag) { console.log('[E]', tag, format(arguments)); },
    fatal: function (domain, tag) { console.log('[F]', tag, format(arguments)); }
};
export default hilog;
