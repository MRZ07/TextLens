import Foundation
import XCTest
@testable import TextLensApp

@MainActor
final class LoginItemControllerTests: XCTestCase {
    func testFirstRunDeclineDoesNotChangeServiceAndIsNotAskedAgain() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService()
        let controller = LoginItemController(service: service, defaults: defaults)

        XCTAssertTrue(controller.shouldAskOnFirstRun)

        controller.respondToFirstRunPrompt(enable: false)

        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
        XCTAssertEqual(controller.state, .notRegistered)
        XCTAssertFalse(controller.shouldAskOnFirstRun)

        let relaunchedController = LoginItemController(service: service, defaults: defaults)
        XCTAssertFalse(relaunchedController.shouldAskOnFirstRun)
    }

    func testFirstRunEnableRegistersAndPersistsOnlyThePromptAnswer() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService()
        let controller = LoginItemController(service: service, defaults: defaults)

        controller.respondToFirstRunPrompt(enable: true)

        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.unregisterCalls, 0)
        XCTAssertEqual(controller.state, .enabled)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertFalse(controller.shouldAskOnFirstRun)
        XCTAssertEqual(
            try XCTUnwrap(defaults.persistentDomain(forName: suiteName)).count,
            1,
            "Login-item preferences should store only the first-run prompt answer."
        )
    }

    func testExistingRegistrationAndPendingApprovalSuppressAndRememberPrompt() {
        for status in [LoginItemServiceStatus.enabled, .requiresApproval] {
            let (defaults, suiteName) = makeDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let service = FakeLoginItemService(status: status)
            let controller = LoginItemController(service: service, defaults: defaults)

            XCTAssertFalse(controller.shouldAskOnFirstRun)
            XCTAssertTrue(controller.isRegistered)

            service.status = .notRegistered
            controller.refresh()

            XCTAssertEqual(controller.state, .notRegistered)
            XCTAssertFalse(controller.shouldAskOnFirstRun)
            XCTAssertEqual(service.registerCalls, 0)
            XCTAssertEqual(service.unregisterCalls, 0)
        }
    }

    func testNotFoundStatusAllowsFirstRunConsentAndRegistrationAttempt() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: .notFound)
        let controller = LoginItemController(service: service, defaults: defaults)

        XCTAssertEqual(controller.state, .notRegistered)
        XCTAssertTrue(controller.shouldAskOnFirstRun)

        controller.respondToFirstRunPrompt(enable: true)

        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.status, .enabled)
        XCTAssertEqual(controller.state, .enabled)
        XCTAssertFalse(controller.shouldAskOnFirstRun)
    }

    func testEnableAndDisableStateIsDerivedFromServiceStatus() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService()
        let controller = LoginItemController(service: service, defaults: defaults)

        controller.setEnabled(true)
        XCTAssertEqual(controller.state, .enabled)
        XCTAssertTrue(controller.isRegistered)

        controller.setEnabled(false)
        XCTAssertEqual(controller.state, .notRegistered)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.unregisterCalls, 1)
    }

    func testRefreshReflectsExternalChangesWithoutReaskingAfterDisable() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService()
        let controller = LoginItemController(service: service, defaults: defaults)

        service.status = .requiresApproval
        controller.refresh()
        XCTAssertEqual(controller.state, .requiresApproval)
        XCTAssertTrue(controller.isRegistered)

        service.status = .notRegistered
        controller.refresh()
        XCTAssertEqual(controller.state, .notRegistered)
        XCTAssertFalse(controller.shouldAskOnFirstRun)
    }

    func testFailedRegistrationAndUnregistrationKeepActualStateAndExposeErrors() throws {
        let (registerDefaults, registerSuite) = makeDefaults()
        defer { registerDefaults.removePersistentDomain(forName: registerSuite) }
        let registrationService = FakeLoginItemService(
            status: .notFound,
            registerError: LoginItemTestError.register
        )
        let registrationController = LoginItemController(service: registrationService, defaults: registerDefaults)

        registrationController.setEnabled(true)

        XCTAssertEqual(registrationController.state, .notRegistered)
        XCTAssertFalse(registrationController.isRegistered)
        XCTAssertEqual(registrationService.status, .notFound)
        XCTAssertTrue(try XCTUnwrap(registrationController.errorMessage).contains("register failed"))
        registrationController.clearError()
        XCTAssertNil(registrationController.errorMessage)

        let (unregisterDefaults, unregisterSuite) = makeDefaults()
        defer { unregisterDefaults.removePersistentDomain(forName: unregisterSuite) }
        let unregistrationService = FakeLoginItemService(
            status: .enabled,
            unregisterError: LoginItemTestError.unregister
        )
        let unregistrationController = LoginItemController(service: unregistrationService, defaults: unregisterDefaults)

        unregistrationController.setEnabled(false)

        XCTAssertEqual(unregistrationController.state, .enabled)
        XCTAssertTrue(unregistrationController.isRegistered)
        XCTAssertTrue(try XCTUnwrap(unregistrationController.errorMessage).contains("unregister failed"))
    }

    func testUnavailableServiceCannotBeEnabledAndOffersActionableError() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: .unknown)
        let controller = LoginItemController(service: service, defaults: defaults)

        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertFalse(controller.shouldAskOnFirstRun)

        controller.setEnabled(true)

        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertTrue(try XCTUnwrap(controller.errorMessage).contains("unknown login-item status"))
    }

    func testOpenSystemSettingsUsesNativeLoginItemsRoute() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService()
        let controller = LoginItemController(service: service, defaults: defaults)

        controller.openSystemSettings()

        XCTAssertEqual(service.openSettingsCalls, 1)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "TextLensLoginItemControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemServicing {
    var status: LoginItemServiceStatus
    var registerError: LoginItemTestError?
    var unregisterError: LoginItemTestError?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    private(set) var openSettingsCalls = 0

    init(
        status: LoginItemServiceStatus = .notRegistered,
        registerError: LoginItemTestError? = nil,
        unregisterError: LoginItemTestError? = nil
    ) {
        self.status = status
        self.registerError = registerError
        self.unregisterError = unregisterError
    }

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {
        openSettingsCalls += 1
    }
}

private enum LoginItemTestError: LocalizedError {
    case register
    case unregister

    var errorDescription: String? {
        switch self {
        case .register: "register failed"
        case .unregister: "unregister failed"
        }
    }
}
