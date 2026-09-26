enum RouteBarWindowPresentation: Equatable {
  case activateApplication
  case keepApplicationState
}

enum RouteBarWindowPresentationRequest: Equatable {
  case foregroundLaunch
  case backgroundLaunch
  case explicitUserAction
  case dockReopen(applicationIsActive: Bool, hasVisibleWindows: Bool)

  var presentation: RouteBarWindowPresentation? {
    switch self {
    case .foregroundLaunch, .explicitUserAction:
      .activateApplication
    case .backgroundLaunch:
      nil
    case .dockReopen(let applicationIsActive, let hasVisibleWindows):
      applicationIsActive && !hasVisibleWindows ? .keepApplicationState : nil
    }
  }
}
