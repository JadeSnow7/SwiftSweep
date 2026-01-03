import Combine
import Foundation

@MainActor
public final class AppStore: ObservableObject {
  public static let shared = AppStore()

  @Published public private(set) var state: AppState

  // Dependencies
  private let scheduler: ConcurrentScheduler

  // Provide a way to inject effects handler later
  public typealias EffectHandler = (AppAction, AppStore) async -> Void
  private var effectHandler: EffectHandler?

  public init(
    initial: AppState = .init(),
    scheduler: ConcurrentScheduler = .shared
  ) {
    self.state = initial
    self.scheduler = scheduler
  }

  public func setEffectHandler(_ handler: @escaping EffectHandler) {
    self.effectHandler = handler
  }

  public func dispatch(_ action: AppAction) {
    // 1. Reduce (Pure State Mutation)
    // Runs on MainActor directly as it drives UI
    state = appReducer(state, action)

    // 2. Side effects (Asynchronous)
    // Dispatch to background via Task
    Task {
      await effectHandler?(action, self)
    }
  }
}
