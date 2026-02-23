import Combine
import Foundation

/// The central state container for SwiftSweep's Unidirectional Data Flow architecture.
///
/// `AppStore` manages the application's global state and coordinates state updates through
/// a unidirectional flow: Actions → Reducer → New State → Effects.
///
/// ## Architecture
///
/// ```
/// User Action → dispatch() → Reducer → New State → UI Update
///                    ↓
///                 Effects (async operations)
/// ```
///
/// ## Usage
///
/// ```swift
/// // Access the shared store
/// let store = AppStore.shared
///
/// // Observe state changes
/// store.$state
///   .map(\.cleanup.items)
///   .sink { items in
///     print("Cleanup items updated: \(items.count)")
///   }
///
/// // Dispatch actions
/// store.dispatch(.cleanup(.startScan))
///
/// // Wait for effects to complete
/// await store.dispatch(.cleanup(.executeCleanup(items)))
/// ```
///
/// ## Thread Safety
///
/// `AppStore` is marked with `@MainActor` to ensure all state updates occur on the main thread,
/// making it safe for UI updates.
///
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

    Task {
      try? await WorkspaceDatabase.shared.setupSchema()
    }
  }

  public func setEffectHandler(_ handler: @escaping EffectHandler) {
    self.effectHandler = handler
  }

  /// Dispatches an action to update the application state.
  ///
  /// This is the primary method for triggering state changes in the application.
  /// The action flows through the reducer to produce a new state, then triggers
  /// any associated side effects.
  ///
  /// - Parameter action: The ``AppAction`` to dispatch
  ///
  /// ## Example
  ///
  /// ```swift
  /// // Dispatch a simple action
  /// store.dispatch(.cleanup(.startScan))
  ///
  /// // Dispatch with data
  /// store.dispatch(.cleanup(.scanCompleted(items)))
  ///
  /// // Dispatch navigation
  /// store.dispatch(.navigation(.navigateTo(.cleanup)))
  /// ```
  ///
  /// ## Thread Safety
  ///
  /// This method must be called from the main thread (enforced by `@MainActor`).
  /// Effects are automatically dispatched to background threads as needed.
  ///
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
