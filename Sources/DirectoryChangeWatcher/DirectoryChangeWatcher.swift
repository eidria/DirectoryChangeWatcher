//
//  DirectoryChangeWatcher.swift
//  DirectoryChangeWatcher
//
//  Created by Dan Galbraith on 12/29/22.
//

import Foundation
import os

public enum DirectoryChange: Sendable {
    case watchedDirectoryChanged(URL)
    case presentedItemMoved(URL)
    case presentedItemChanged(String)
    case presentedItemDeleted(URL)
    case subItemAdded(URL)
    case subItemChanged(URL)
    case subItemMoved(URL, URL)
    case subItemDeleted(URL)
    case unknown(String)

    public func description() -> String {
        switch self {
        case let .watchedDirectoryChanged(url):
            return "Watched Directory Changed: \(url)"
        case let .presentedItemMoved(url):
            return "Presented Item Moved: \(url)"
        case let .presentedItemChanged(description):
            return "Presented Item Changed: \(description)"
        case let .presentedItemDeleted(url):
            return "Presented Item Deleted: \(url)"
        case let .subItemAdded(url):
            return "Presented Item Added: \(url)"
        case let .subItemChanged(url):
            return "Sub Item Changed: \(url)"
        case let .subItemMoved(from, to):
            return "Sub Item Moved: \(from) to \(to)"
        case let .subItemDeleted(url):
            return "Sub Item Deleted: \(url)"
        case let .unknown(desc):
            return "Unknown Change: \(desc)"
        }
    }
}

public final class DirectoryChangeWatcher: NSObject, NSFilePresenter, Sendable {
    public typealias Stream = AsyncStream<DirectoryChange>
    public typealias Continuation = Stream.Continuation
    public typealias BufferingPolicy = Continuation.BufferingPolicy

    public let presentedItemOperationQueue = OperationQueue.main
    public let presentedItemURL: URL?
    
    public let stream: Stream
    private let continuation: Continuation
    
    /// Tracks whether the watcher has been stopped to prevent double-removal
    private let isStopped = OSAllocatedUnfairLock(initialState: false)
    
    public init(_ url: URL) {
        var tempContinuation: Stream.Continuation?
        stream = Stream(bufferingPolicy: .unbounded) { continuation in
            tempContinuation = continuation
        }
        
        continuation = tempContinuation!
        presentedItemURL = url
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }
    
    /// Stops watching for directory changes and releases system resources.
    ///
    /// Call this method when you're done observing directory changes. This removes
    /// the file presenter from `NSFileCoordinator` and finishes the async stream.
    ///
    /// - Important: You must call this method to allow the `DirectoryChangeWatcher`
    ///   to be deallocated, since `NSFileCoordinator` holds a strong reference to
    ///   file presenters. Failing to call `stop()` will result in a memory leak.
    ///
    /// It is safe to call this method multiple times.
    public func stop() {
        isStopped.withLock { stopped in
            guard !stopped else { return }
            stopped = true
            continuation.finish()
            NSFileCoordinator.removeFilePresenter(self)
        }
    }

    deinit {
        // Ensure cleanup happens even if stop() wasn't called explicitly
        stop()
    }
}

public extension DirectoryChangeWatcher {
    /* Given that something in the system is waiting to read from the presented file or directory, do whatever it takes to ensure that the application will behave properly while that reading is happening, and then invoke the completion handler. The definition of "properly" depends on what kind of ownership model the application implements. Implementations of this method must always invoke the passed-in reader block because other parts of the system will wait until it is invoked or until the user loses patience and cancels the waiting. When an implementation of this method invokes the passed-in block it can pass that block yet another block, which will be invoked in the receiver's operation queue when reading is complete.

     A common sequence that your NSFilePresenter must handle is the file coordination mechanism sending this message, then sending -savePresentedItemChangesWithCompletionHandler:, and then, after you have invoked that completion handler, invoking your reacquirer.
     */
    func relinquishPresentedItem(toReader reader: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        continuation.yield(.unknown("relinquishPresentedItem toReader"))
        reader({})
    }

    /* Given that something in the system is waiting to write to the presented file or directory, do whatever it takes to ensure that the application will behave properly while that writing is happening, and then invoke the completion handler. The definition of "properly" depends on what kind of ownership model the application implements. Implementations of this method must always invoke the passed-in writer block because other parts of the system will wait until it is invoked or until the user loses patience and cancels the waiting. When an implementation of this method invokes the passed-in block it can pass that block yet another block, which will be invoked in the receiver's operation queue when writing is complete.

     A common sequence that your NSFilePresenter must handle is the file coordination mechanism sending this message, then sending -accommodatePresentedItemDeletionWithCompletionHandler: or -savePresentedItemChangesWithCompletionHandler:, and then, after you have invoked that completion handler, invoking your reacquirer. It is also common for your NSFilePresenter to be sent a combination of the -presented... messages listed below in between relinquishing and reacquiring.
     */
    func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        continuation.yield(.unknown("relinquishPresentedItem toWriter"))
        writer({})
    }

    /* Given that something in the system is waiting to read from the presented file or directory, do whatever it takes to ensure that the contents of the presented file or directory is completely up to date, and then invoke the completion handler. If successful (including when there is simply nothing to do) pass nil to the completion handler, or if not successful pass an NSError that encapsulates the reason why saving failed. Implementations of this method must always invoke the completion handler because other parts of the system will wait until it is invoked or the user loses patience and cancels the waiting. If this method is not implemented then the NSFilePresenter is assumed to be one that never lets the user make changes that need to be saved.

     For example, NSDocument has an implementation of this method that autosaves the document if it has been changed since the last time it was saved or autosaved. That way when another process tries to read the document file it always reads the same version of the document that the user is looking at in your application. (WYSIWGCBF - What You See Is What Gets Copied By Finder.) A shoebox application would also implement this method.

     The file coordination mechanism does not always send -relinquishPresentedItemToReader: or -relinquishPresentedItemToWriter: to your NSFilePresenter before sending this message. For example, other process' use of -[NSFileCoordinator prepareForReadingItemsAtURLs:options:writingItemsAtURLs:options:error:byAccessor:] can cause this to happen.
     */
    func savePresentedItemChanges(completionHandler: @escaping @Sendable (Error?) -> Void) {
        continuation.yield(.unknown("savePresentedItemChanges"))
        completionHandler(nil)
    }

    //    public func savePresentedItemChanges() async throws {
    //
    //    }
    //

    /* Given that something in the system is waiting to delete the presented file or directory, do whatever it takes to ensure that the deleting will succeed and that the receiver's application will behave properly when the deleting has happened, and then invoke the completion handler. If successful (including when there is simply nothing to do) pass nil to the completion handler, or if not successful pass an NSError that encapsulates the reason why preparation failed. Implementations of this method must always invoke the completion handler because other parts of the system will wait until it is invoked or until the user loses patience and cancels the waiting.

     For example, NSDocument has an implementation of this method that closes the document. That way if the document is in the trash and the user empties the trash the document is simply closed before its file is deleted. This means that emptying the trash will not fail with an alert about the file being "in use" just because the document's file is memory mapped by the application. It also means that the document won't be left open with no document file underneath it. A shoebox application would only implement this method to be robust against surprising things like the user deleting its data directory while the application is running.

     The file coordination mechanism does not always send -relinquishPresentedItemToReader: or -relinquishPresentedItemToWriter: to your NSFilePresenter before sending this message. For example, other process' use of -[NSFileCoordinator prepareForReadingItemsAtURLs:options:writingItemsAtURLs:options:error:byAccessor:] can cause this to happen.
     */
    func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable (Error?) -> Void) {
        let lastChange = "accommodatePresentedItemDeletion"
        continuation.yield(.unknown(lastChange))
        completionHandler(nil)
    }

    //    public func accommodatePresentedItemDeletion() async throws {
    //
    //    }
    //

    /* Be notified that the file or directory has been moved or renamed, or a directory containing it has been moved or renamed. A typical implementation of this method will cause subsequent invocations of -presentedItemURL to return the new URL.

     The new URL may have a different file name extension than the current value of the presentedItemURL property.

     For example, NSDocument implements this method to handle document file moving and renaming. A shoebox application would only implement this method to be robust against surprising things like the user moving its data directory while the application is running.

     Not all programs use file coordination. Your NSFileProvider may be sent this message without being sent -relinquishPresentedItemToWriter: first. Make your application do the best it can in that case.
     */
    func presentedItemDidMove(to newURL: URL) {
        continuation.yield(.presentedItemMoved(newURL))
    }

    /* These messages are sent by the file coordination machinery only when the presented item is a file or file package.
     */

    /* Be notified that the file or file package's contents or attributes have been been written to. Because this method may be be invoked when the attributes have changed but the contents have not, implementations that read the contents must use modification date checking to avoid needless rereading. They should check that the modification date has changed since the receiver most recently read from or wrote to the item. To avoid race conditions, getting the modification date should typically be done within invocations of one of the -[NSFileCoordinator coordinate...] methods.

     For example, NSDocument implements this method to react to both contents changes (like the user overwriting the document file with another application) and attribute changes (like the user toggling the "Hide extension" checkbox in a Finder info panel). It uses modification date checking as described above.

     Not all programs use file coordination. Your NSFileProvider may be sent this message without being sent -relinquishPresentedItemToWriter: first. Make your application do the best it can in that case.
     */
    func presentedItemDidChange() {
        continuation.yield(.presentedItemChanged(String(describing: presentedItemURL)))
    }

    /* Be notified that the presented file or file package's ubiquity attributes have changed. The possible attributes that can appear in the given set include only those specified by the receiver's value for observedPresentedItemUbiquityAttributes, or those in the default set if that property is not implemented.

     Note that changes to these attributes do not normally align with -presentedItemDidChange notifications.
     */
    func presentedItemDidChangeUbiquityAttributes(_ attributes: Set<URLResourceKey>) {
        let lastChange = "presentedItemDidChangeUbiquityAttributes to \(attributes)"
        continuation.yield(.unknown(lastChange))
    }

    /* The set of ubiquity attributes, which the receiver wishes to be notified about when they change for presentedItemURL. Valid attributes include only NSURLIsUbiquitousItemKey and any other attributes whose names start with "NSURLUbiquitousItem" or "NSURLUbiquitousSharedItem". The default set, in case this property is not implemented, includes of all such attributes.

     This property will normally be checked only at the time addFilePresenter: is called. However, if presentedItemURL is nil at that time, it will instead be checked only at the end of a coordinated write where presentedItemURL became non-nil. The value of this property should not change depending on whether presentedItemURL is currently ubiquitous or is located a ubiquity container.

     For example, NSDocument implements this property to always return NSURLIsUbiquitousItemKey, NSURLUbiquitousItemIsSharedKey, and various other properties starting with "NSURLUbiquitousSharedItem". It needsto be notified about changes to these properties in order to implement support for ubiquitous and shared documents.
     */
    //    public var observedPresentedItemUbiquityAttributes: Set<URLResourceKey> { get }

    /* Be notified that something in the system has added, removed, or resolved a version of the file or file package.

     For example, NSDocument has implementations of these methods that help decide whether to present a versions browser when it has reacquired after relinquishing to a writer, and to react to versions being added and removed while it is presenting the versions browser.
     */
    func presentedItemDidGain(_ version: NSFileVersion) {
        let lastChange = "presentedItemDidGain to \(version)"
        continuation.yield(.unknown(lastChange))
    }

    func presentedItemDidLose(_ version: NSFileVersion) {
        let lastChange = "presentedItemDidLose \(version)"
        continuation.yield(.unknown(lastChange))
    }

    func presentedItemDidResolveConflict(_ version: NSFileVersion) {
        let lastChange = "presentedItemDidResolveConflict to \(version)"
        continuation.yield(.unknown(lastChange))
    }

    /* These methods are sent by the file coordination machinery only when the presented item is a directory. "Contained by the directory" in these comments means contained by the directory, a directory contained by the directory, and so on.
     */

    /* Given that something in the system is waiting to delete a file or directory contained by the directory, do whatever it takes to ensure that the deleting will succeed and that the receiver's application will behave properly when the deleting has happened, and then invoke the completion handler. If successful (including when there is simply nothing to do) pass nil to the completion handler, or if not successful pass an NSError that encapsulates the reason why preparation failed. Implementations of this method must always invoke the completion handler because other parts of the system will wait until it is invoked or until the user loses patience and cancels the waiting.

     The file coordination mechanism does not always send -relinquishPresentedItemToReader: or -relinquishPresentedItemToWriter: to your NSFilePresenter before sending this message. For example, other process' use of -[NSFileCoordinator prepareForReadingItemsAtURLs:options:writingItemsAtURLs:options:error:byAccessor:] can cause this to happen.
     */
    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping @Sendable (Error?) -> Void) {
        let lastChange = "accommodatePresentedSubitemDeletion at \(url)"
        completionHandler(nil)
        continuation.yield(.unknown(lastChange))
    }

    //    public func accommodatePresentedSubitemDeletion(at url: URL) async throws {
    //
    //    }

    /* Be notified that a file or directory contained by the directory has been added. If this method is not implemented but -presentedItemDidChange is, and the directory is actually a file package, then the file coordination machinery will invoke -presentedItemDidChange instead.

     Not all programs use file coordination. Your NSFileProvider may be sent this message without being sent -relinquishPresentedItemToWriter: first. Make your application do the best it can in that case.
     */
    func presentedSubitemDidAppear(at url: URL) {
        continuation.yield(.subItemAdded(url))
    }

    /* Be notified that a file or directory contained by the directory has been moved or renamed. If this method is not implemented but -presentedItemDidChange is, and the directory is actually a file package, then the file coordination machinery will invoke -presentedItemDidChange instead.

     Not all programs use file coordination. Your NSFileProvider may be sent this message without being sent -relinquishPresentedItemToWriter: first. Make your application do the best it can in that case.
     */
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        continuation.yield(.subItemMoved(oldURL, newURL))
    }

    /* Be notified that the contents or attributes of a file or directory contained by the directory have been been written to. Depending on the situation the advice given for -presentedItemDidChange may apply here too. If this method is not implemented but -presentedItemDidChange is, and the directory is actually a file package, then the file coordination machinery will invoke -presentedItemDidChange instead.

     Not all programs use file coordination. Your NSFileProvider may be sent this message without being sent -relinquishPresentedItemToWriter: first. Make your application do the best it can in that case.
     */
    func presentedSubitemDidChange(at url: URL) {
        if url.lastPathComponent != ".DS_Store" {
            continuation.yield(.subItemChanged(url))
        }
    }

    /* Be notified that the something in the system has added, removed, or resolved a version of a file or directory contained by the directory.
     */
    func presentedSubitem(at url: URL, didGain version: NSFileVersion) {
        let lastChange = "presentedSubitem at \(url) didGain \(version)"
        continuation.yield(.unknown(lastChange))
    }

    func presentedSubitem(at url: URL, didLose version: NSFileVersion) {
        let lastChange = "presentedSubitem at \(url) didLose \(version)"
        continuation.yield(.unknown(lastChange))
    }

    func presentedSubitem(at url: URL, didResolve version: NSFileVersion) {
        let lastChange = "presentedSubitem at \(url) didResolve \(version)"
        continuation.yield(.unknown(lastChange))
    }
}
