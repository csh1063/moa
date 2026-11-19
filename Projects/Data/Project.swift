import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.framework(module: Module.data,
                                dependencies: [Module.domain.project]
                                + [.moya, .combineMoya, .firebaseCore, .firebaseInstallations],
                                resources: [
                                    .glob(pattern: "Resources/**", excluding: [
//                                        "Resources/AdaFace_IR50.mlpackage/**",
//                                        "Resources/AnimalReID_DINOv2.mlpackage/**"
                                        "Resources/Models/**"
                                    ]),
                                    .folderReference(path: "Resources/Models/AdaFace_IR50.mlpackage"),
                                    .folderReference(path: "Resources/Models/AnimalReID_DINOv2.mlpackage")
                                ]
)
