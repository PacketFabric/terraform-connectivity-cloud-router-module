## 0.3.1  (May 25, 2023)

IMPROVEMENTS/ENHANCEMENTS:

* Remove module_variable_optional_attrs experiments and bump terraform minimum version to 1.3 (#7)

## 0.3.0  (May 25, 2023)

BREAKING CHANGES:

* Remove Total price MRC (monthly recurring cost) for the Cloud Router and all Cloud Router Connections (#6)

FEATURES:

* Adding Azure standalone or redundant Cloud Router Connection support (#6)
* Adding name and labels attributes to individual Cloud Router Conections (#6)
* Adding support of multiple Google and AWS Cloud Router Connections (#6)
* Adding option to specify an existing PacketFabric Cloud Router (#6)
* Add module_variable_optional_attrs experiments and update terraform supported version to >= 1.1.0, < 1.3.0 for CTS module support (#6)

## 0.2.1  (May 8, 2023)

IMPROVEMENTS/ENHANCEMENTS:

* Add Total price MRC (monthly recurring cost) for the Cloud Router and all Cloud Router Connections (#4)
* Updated the default Cloud Router Region to US only (#4)

## 0.2.0  (May 5, 2023)

IMPROVEMENTS/ENHANCEMENTS:

* Remove module_variable_optional_attrs experiments and bump terraform minimum version to 1.3 (#3)
* Add provider "aws" in aws sub-module (#3)

## 0.1.0  (May 4, 2023)

FEATURES:

* Create a PacketFabric Cloud Router with either standalone or redundant connection between AWS and Google Clouds
