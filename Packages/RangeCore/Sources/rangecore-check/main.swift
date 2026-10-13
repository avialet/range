#if DEBUG
import RangeCore

run([
    databaseTests,
    filesTests,
    readerTests,
    ruleTests,
    plannerTests,
    applyTests,
    undoTests,
    engineTests,
    recoveryTests,
])
#else
print("tests : configuration debug seulement")
#endif
