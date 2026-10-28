# Interner Zugang für den künstlichen Alltagstest

Die öffentliche Testphase und Bestellfunktion bleiben ausgeschaltet. Für den
ausdrücklich beauftragten Alltagstest gibt es einen lokalen, einmaligen
Operatorbefehl `python -m schulpilot.private_qa_access`, keinen öffentlichen
Endpunkt. Er akzeptiert nur die Kennungen der verifizierten, eigens für diesen
Test angelegten Familie und deren einzelnen Kinderzugangs sowie die zwei bereits
gespeicherten künstlichen Fotos. Der Befehl prüft Familienmitgliedschaft,
Testalias, Kinderzugang, Inhaltssummen, fehlende frühere Aufträge und Lernbelege
und den unveränderten öffentlichen Testphasenstatus. Er verändert keine anderen
Familien, startet keine KI und protokolliert keine Foto- oder Antwortinhalte.

Die Freigabe verwendet die bestehende Testphasenbuchung für höchstens 30 Tage,
100 Aufrufe und 15 USD. Jeder Auftrag unterliegt weiterhin den normalen
Reservierungen, Provider-, Sitzungs-, Datenschutz- und Globalgrenzen. Der
Datensatz trägt die eigene Version `private-photo-qa-20261028-1`; die lokale
Anlage ist gesondert auditierbar und idempotent. Es wird kein Zahlungseingang
behauptet. Die Begrenzung ist eine technische Obergrenze, keine Kostenzusage.

Die Prüfung der beiden künstlichen Fotos erfolgt bei Anlage. Weitere Uploads im
internen Testkonto müssen weiterhin ausdrücklich künstlich sein; die Prüfung
ist kein allgemeiner Filter für später ausgewählte Fotos. Das private Konto und
seine Zugangsdaten bleiben beim Betreiber. Die reguläre Kontolöschung entfernt
auch die Testbuchung; ohne solche Löschung endet sie automatisch nach 30 Tagen.
