"""Standalone synthetic AST tests; no app imports, DB, HTTP or provider execution.
Run as python3 <file>. This is a review candidate, not a transport/full-suite gate.
"""
import ast
import sys
import types
import unittest
from pathlib import Path

BACKEND=Path(__file__).resolve().parents[1]
TREE=ast.parse((BACKEND/'schulpilot/providers.py').read_text())
DEFINITIONS={n.name:n for n in TREE.body if isinstance(n,(ast.FunctionDef,ast.ClassDef))}
FAILURES=ast.parse((BACKEND/'schulpilot/job_failures.py').read_text())
CODES=next(ast.literal_eval(n.value) for n in FAILURES.body
    if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='CODES' for t in n.targets))
FAKE=types.ModuleType('synthetic_provider_package.job_failures')
FAKE.CODES=CODES
FAKE.message_code=lambda _message:'unknown'
sys.modules[FAKE.__name__]=FAKE
SCOPE={'__package__':'synthetic_provider_package'}
exec(compile(ast.fix_missing_locations(ast.Module(body=[DEFINITIONS[name] for name in
    ('ProviderError','openrouter_failure','openrouter_failure_code')],type_ignores=[])),
    '<public-synthetic-provider-definitions>','exec'),SCOPE)

class OpenRouterErrorClassification(unittest.TestCase):
    def test_closed_categories_preserve_exact_public_messages(self):
        for category,code,message in [
            ('rate_limit_exceeded','provider_busy','Die KI ist gerade ausgelastet. Bitte später erneut versuchen.'),
            ('provider_overloaded','provider_busy','Die KI ist gerade ausgelastet. Bitte später erneut versuchen.'),
            ('timeout','provider_timeout','Die KI hat zu lange gebraucht und abgebrochen. Bitte später erneut versuchen.'),
            ('authentication','provider_unavailable','Die KI-Verbindung muss vom Betreiber geprüft werden. Deine Fotos bleiben gespeichert.'),
            ('permission_denied','provider_unavailable','Die KI-Verbindung muss vom Betreiber geprüft werden. Deine Fotos bleiben gespeichert.'),
            ('payment_required','provider_unavailable','Die KI-Verbindung muss vom Betreiber geprüft werden. Deine Fotos bleiben gespeichert.'),
            ('invalid_request','provider_unavailable','Die KI-Verbindung muss vom Betreiber geprüft werden. Deine Fotos bleiben gespeichert.'),
            ('server','provider_unavailable','Der KI-Anbieter hat die Antwort abgebrochen. Bitte später erneut versuchen.'),
        ]:
            with self.subTest(category=category):
                value={'metadata':{'error_type':category,'raw':'PRIVATE-SYNTHETIC'},'message':'PRIVATE-SYNTHETIC'}
                self.assertEqual(SCOPE['openrouter_failure_code'](value),code)
                self.assertEqual(SCOPE['openrouter_failure'](value),message)
                error=SCOPE['ProviderError'](message,code=code)
                self.assertEqual(error.code,code)
                self.assertIsNone(error.billing_result)
                self.assertNotIn('PRIVATE-SYNTHETIC',str(error))

    def test_unknown_and_malformed_envelopes_are_unavailable_without_zero_cost_claim(self):
        for value in (None,[],0,'PRIVATE-SYNTHETIC',{}, {'metadata':[]},
                {'metadata':{'error_type':None}}, {'metadata':{'error_type':'future_unknown'}},
                {'metadata':{'error_type':['timeout']}}, {'code':429,'message':'PRIVATE-SYNTHETIC'}):
            with self.subTest(shape=type(value).__name__):
                self.assertEqual(SCOPE['openrouter_failure_code'](value),'provider_unavailable')
                self.assertEqual(SCOPE['openrouter_failure'](value),
                    'Der KI-Anbieter hat die Antwort abgebrochen. Bitte später erneut versuchen.')
                self.assertIsNone(SCOPE['ProviderError'](SCOPE['openrouter_failure'](value),
                    code=SCOPE['openrouter_failure_code'](value)).billing_result)

    def test_both_actual_error_raise_hooks_forward_same_envelope_and_only_add_code(self):
        hooks=[]
        for node in ast.walk(DEFINITIONS['request_provider']):
            if (isinstance(node,ast.Raise) and isinstance(node.exc,ast.Call)
                    and isinstance(node.exc.func,ast.Name) and node.exc.func.id=='ProviderError'
                    and node.exc.args and isinstance(node.exc.args[0],ast.Call)
                    and isinstance(node.exc.args[0].func,ast.Name)
                    and node.exc.args[0].func.id=='openrouter_failure'):
                call=node.exc
                self.assertEqual(len(call.args),1)
                self.assertEqual([k.arg for k in call.keywords],['code'])
                code=call.keywords[0].value
                self.assertIsInstance(code,ast.Call)
                self.assertEqual(code.func.id,'openrouter_failure_code')
                self.assertEqual(ast.dump(code.args[0]),ast.dump(call.args[0].args[0]))
                hooks.append(ast.unparse(code.args[0]))
        self.assertCountEqual(hooks,["raw['error']","choice['error']"])

if __name__=='__main__':
    unittest.main(verbosity=2)
