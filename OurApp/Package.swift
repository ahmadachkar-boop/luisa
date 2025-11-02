// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OurApp",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "OurApp",
            targets: ["OurApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.18.0")
    ],
    targets: [
        .target(
            name: "OurApp",
            dependencies: [
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseStorage", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk")
            ],
            path: "OurApp"
        )
    ]
)
