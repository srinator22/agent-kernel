# Experiments, models, leakage, validation status

- Start from an accepted reference or a hand-calculated fixture; record
  input, expected output, units, source, precision, and tolerance.
- Derive the tolerance from the reference and the use case; do not default
  to 1 percent unless that is the accepted contract.
- Seeds are deterministic and stored with the parameters they seeded.
- Never change expected values to match a new implementation. If the
  reference itself is wrong, document the evidence and the decision first;
  the fixture change is its own reviewed commit.
- Independent runs stay independent groups; never pool them into one
  sample as if they were repeated measurements.
- Split train/validation by run group to prevent leakage.
- Report the independent-run count, uncertainty, and limitations with any
  result; a model built on a few runs is a prototype and is labeled one.
- Software verification is not field or regulatory validation. State the
  validation status honestly: built, trained, evaluated, validated,
  deployed, and production-ready are different claims (kernel rule 14).
