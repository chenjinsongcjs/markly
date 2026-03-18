//
//  AutoSaveManager.swift
//  Markly
//
//  Created by Codex on 2026/3/18.
//

import Foundation
import Combine

/// 自动保存管理器
@MainActor
final class AutoSaveManager: ObservableObject {
    // MARK: - Singleton
    static let shared = AutoSaveManager()

    // MARK: - Published Properties
    @Published var isAutoSaving: Bool = false
    @Published var lastAutoSaveTime: Date?

    // MARK: - Private Properties
    private var timer: Timer?
    private var pendingChanges: [URL: String] = [:]
    private var saveCallbacks: [URL: ((URL) -> Void)] = [:]
    private var debouncedSaves: [URL: Timer] = [:]

    // MARK: - Initialization
    private init() {
        startAutoSaveTimer()
    }

    // MARK: - Public Methods

    /// 注册文件的保存回调
    /// - Parameters:
    ///   - url: 文件 URL
    ///   - callback: 保存回调函数
    func registerFile(url: URL, callback: @escaping (URL) -> Void) {
        saveCallbacks[url] = callback
    }

    /// 注销文件
    /// - Parameter url: 文件 URL
    func unregisterFile(url: URL) {
        saveCallbacks.removeValue(forKey: url)
        pendingChanges.removeValue(forKey: url)
        cancelDebouncedSave(for: url)
    }

    /// 通知有待保存的更改
    /// - Parameters:
    ///   - url: 文件 URL
    ///   - content: 新内容
    func notifyPendingChange(for url: URL, content: String) {
        pendingChanges[url] = content

        // 如果启用了自动保存，设置防抖定时器
        if EditorPreferences.shared.autoSaveInterval > 0 {
            scheduleDebouncedSave(for: url)
        }
    }

    /// 立即保存指定文件
    /// - Parameter url: 文件 URL
    func saveImmediately(url: URL) {
        guard let callback = saveCallbacks[url] else { return }
        cancelDebouncedSave(for: url)

        isAutoSaving = true
        callback(url)
        lastAutoSaveTime = Date()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor in
                self?.isAutoSaving = false
            }
        }
    }

    /// 立即保存所有待更改的文件
    func saveAll() {
        for url in pendingChanges.keys {
            saveImmediately(url: url)
        }
    }

    /// 清除待保存的更改（用于文件已保存的情况）
    /// - Parameter url: 文件 URL
    func clearPendingChange(for url: URL) {
        pendingChanges.removeValue(forKey: url)
    }

    // MARK: - Timer Management

    private func startAutoSaveTimer() {
        stopAutoSaveTimer()

        let interval = EditorPreferences.shared.autoSaveInterval
        guard interval > 0 else { return }

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.performAutoSave()
            }
        }
    }

    private func stopAutoSaveTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// 重新启动自动保存定时器（当间隔设置改变时调用）
    func restartAutoSaveTimer() {
        startAutoSaveTimer()
    }

    // MARK: - Debounced Save

    private func scheduleDebouncedSave(for url: URL) {
        cancelDebouncedSave(for: url)

        let interval = EditorPreferences.shared.autoSaveInterval
        guard interval > 0 else { return }

        let debounceTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveImmediately(url: url)
            }
        }

        debouncedSaves[url] = debounceTimer
    }

    private func cancelDebouncedSave(for url: URL) {
        debouncedSaves[url]?.invalidate()
        debouncedSaves.removeValue(forKey: url)
    }

    private func cancelAllDebouncedSaves() {
        debouncedSaves.values.forEach { $0.invalidate() }
        debouncedSaves.removeAll()
    }

    // MARK: - Auto Save Logic

    private func performAutoSave() {
        guard !pendingChanges.isEmpty else { return }

        isAutoSaving = true

        for url in pendingChanges.keys {
            if let callback = saveCallbacks[url] {
                callback(url)
            }
        }

        lastAutoSaveTime = Date()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Task { @MainActor in
                self?.isAutoSaving = false
            }
        }
    }

    // MARK: - Auto Save Preferences Observer

    /// 监听自动保存设置变化
    func observeAutoSavePreferences() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restartAutoSaveTimer()
            }
        }
    }
}

// MARK: - Convenience Extensions

extension AutoSaveManager {
    /// 获取自动保存状态描述
    var autoSaveStatus: String {
        let interval = EditorPreferences.shared.autoSaveInterval

        guard interval > 0 else {
            return "已禁用"
        }

        if isAutoSaving {
            return "正在保存..."
        }

        if let lastSave = lastAutoSaveTime {
            let timeAgo = Date().timeIntervalSince(lastSave)
            if timeAgo < 60 {
                return "刚刚保存"
            } else {
                let minutes = Int(timeAgo / 60)
                return "\(minutes) 分钟前保存"
            }
        }

        return "等待保存"
    }

    /// 下次自动保存的剩余时间（秒）
    var timeUntilNextAutoSave: TimeInterval? {
        guard timer?.isValid == true else { return nil }
        return EditorPreferences.shared.autoSaveInterval
    }
}
