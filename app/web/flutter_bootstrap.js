{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load({onEntrypointLoaded:async function(initializer){const runner=await initializer.initializeEngine();document.getElementById('startup')?.remove();await runner.runApp();}});
