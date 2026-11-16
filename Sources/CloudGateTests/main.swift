import TestKit
import Foundation

let suites: [TestSuite] = [
    cloudGateErrorSuite(),
    redactionSuite(),
    resourceIdentifierSuite(),
    preferencesStoreSuite(),
    redactingLoggerSuite(),
    sessionControllerSuite(),
    discoveryParsingSuite(),
    discoveryServiceSuite(),
    favoritesSuite(),
    iapFrameSuite(),
    terminalEmulatorSuite(),
    connectionManagerSuite(),
    windowsCredentialsSuite(),
    ptySessionSuite()
]

let code = await TestRunner.run(suites)
exit(code)
