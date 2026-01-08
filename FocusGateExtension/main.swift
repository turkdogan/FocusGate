//
//  main.swift
//  PageBlockerExtension
//
//  System extension entry point
//

import Foundation
import NetworkExtension

autoreleasepool {
    // Start the extension
    NEProvider.startSystemExtensionMode()
}

// Run loop to keep the extension alive
dispatchMain()
