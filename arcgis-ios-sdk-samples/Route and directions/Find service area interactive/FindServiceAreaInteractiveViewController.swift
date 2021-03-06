//
// Copyright 2017 Esri.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit
import ArcGIS

class FindServiceAreaInteractiveViewController: UIViewController, AGSGeoViewTouchDelegate, ServiceAreaSettingsViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    @IBOutlet private var mapView: AGSMapView!
    @IBOutlet private var segmentedControl: UISegmentedControl!
    @IBOutlet private var serviceAreaBBI: UIBarButtonItem!
    
    private var facilitiesGraphicsOverlay = AGSGraphicsOverlay()
    private var barriersGraphicsOverlay = AGSGraphicsOverlay()
    private var serviceAreaGraphicsOverlay = AGSGraphicsOverlay()
    private var barrierGraphic: AGSGraphic!
    private var serviceAreaTask: AGSServiceAreaTask!
    private var serviceAreaParameters: AGSServiceAreaParameters!
    
    var firstTimeBreak: Int = 3
    var secondTimeBreak: Int = 8
    
    override func viewDidLoad() {
        super.viewDidLoad()

        //add the source code button item to the right of navigation bar
        (self.navigationItem.rightBarButtonItem as! SourceCodeBarButtonItem).filenames = ["FindServiceAreaInteractiveViewController", "ServiceAreaSettingsViewController"]
        
        //initialize map with basemap
        let map = AGSMap(basemap: .terrainWithLabels())
        
        //center for initial viewpoint
        let center = AGSPoint(x: -13041154, y: 3858170, spatialReference: .webMercator())
        
        //initial viewpoint
        map.initialViewpoint = AGSViewpoint(center: center, scale: 1e5)
        
        //assign map to map view
        self.mapView.map = map
        
        //assign touch delegate as self to know when use interacted with the map view
        //Will be adding facilities and barriers on interaction
        self.mapView.touchDelegate = self
        
        //initialize service area task
        self.serviceAreaTask = AGSServiceAreaTask(url: URL(string: "https://sampleserver6.arcgisonline.com/arcgis/rest/services/NetworkAnalysis/SanDiego/NAServer/ServiceArea")!)
        
        //get default parameters for the task
        self.getDefaultParameters()
        
        //facility picture marker symbol
        let facilitySymbol = AGSPictureMarkerSymbol(image: UIImage(named: "Facility")!)
        
        //offset symbol in Y to align image properly
        facilitySymbol.offsetY = 21
        
        //assign renderer on facilities graphics overlay using the picture marker symbol
        self.facilitiesGraphicsOverlay.renderer = AGSSimpleRenderer(symbol: facilitySymbol)
        
        //barrier symbol
        let barrierSymbol = AGSSimpleFillSymbol(style: .diagonalCross, color: .red, outline: nil)
        
        //set symbol on barrier graphics overlay using renderer
        self.barriersGraphicsOverlay.renderer = AGSSimpleRenderer(symbol: barrierSymbol)
        
        //add graphicOverlays to the map. One for facilities, barriers and service areas
        self.mapView.graphicsOverlays.addObjects(from: [self.serviceAreaGraphicsOverlay, self.barriersGraphicsOverlay, self.facilitiesGraphicsOverlay])
    }
    
    private func getDefaultParameters() {
        //get default parameters
        self.serviceAreaTask.defaultServiceAreaParameters { [weak self] (parameters: AGSServiceAreaParameters?, error: Error?) in
            guard error == nil else {
                self?.presentAlert(message: "Error getting default parameters:: \(error!.localizedDescription)")
                return
            }
            
            //keep a reference to the default parameters to be used later
            self?.serviceAreaParameters = parameters
            
            //enable service area bar button item
            self?.serviceAreaBBI.isEnabled = true
        }
    }
    
    private func serviceAreaSymbol(for index: Int) -> AGSSymbol {
        //fill symbol for service area
        var fillSymbol: AGSSimpleFillSymbol
        
        if index == 0 {
            let lineSymbol = AGSSimpleLineSymbol(style: .solid, color: UIColor(red: 0.4, green: 0.4, blue: 0, alpha: 0.3), width: 2)
            fillSymbol = AGSSimpleFillSymbol(style: .solid, color: UIColor(red: 0.8, green: 0.8, blue: 0, alpha: 0.3), outline: lineSymbol)
        } else {
            let lineSymbol = AGSSimpleLineSymbol(style: .solid, color: UIColor(red: 0, green: 0.4, blue: 0, alpha: 0.3), width: 2)
            fillSymbol = AGSSimpleFillSymbol(style: .solid, color: UIColor(red: 0, green: 0.8, blue: 0, alpha: 0.3), outline: lineSymbol)
        }
        
        return fillSymbol
    }
    
    // MARK: - Actions
    
    @IBAction private func serviceArea() {
        //remove previously added service areas
        serviceAreaGraphicsOverlay.graphics.removeAllObjects()
        
        let facilitiesGraphics = facilitiesGraphicsOverlay.graphics as! [AGSGraphic]
        
        //check if at least a single facility is added
        guard !facilitiesGraphics.isEmpty else {
            presentAlert(message: "At least one facility is required")
            return
        }
        
        //add facilities
        var facilities = [AGSServiceAreaFacility]()
        
        //for each graphic in facilities graphicsOverlay add a facility to the parameters
        for graphic in facilitiesGraphics {
            let point = graphic.geometry as! AGSPoint
            let facility = AGSServiceAreaFacility(point: point)
            facilities.append(facility)
        }
        self.serviceAreaParameters.setFacilities(facilities)
        
        //add barriers
        var barriers = [AGSPolygonBarrier]()
        
        //for each graphic in barrier graphicsOverlay add a barrier to the parameters
        for graphic in barriersGraphicsOverlay.graphics as! [AGSGraphic] {
            let polygon = graphic.geometry as! AGSPolygon
            let barrier = AGSPolygonBarrier(polygon: polygon)
            barriers.append(barrier)
        }
        serviceAreaParameters.setPolygonBarriers(barriers)
        
        //set time breaks
        serviceAreaParameters.defaultImpedanceCutoffs = [NSNumber(value: firstTimeBreak), NSNumber(value: secondTimeBreak)]
        
        serviceAreaParameters.geometryAtOverlap = .dissolve
        
        //show progress hud
        SVProgressHUD.show(withStatus: "Loading")
        
        //solve for service area
        serviceAreaTask.solveServiceArea(with: serviceAreaParameters) { [weak self] (result: AGSServiceAreaResult?, error: Error?) in
            //dismiss progress hud
            SVProgressHUD.dismiss()
            
            guard let self = self else {
                return
            }
            
            if let error = error {
                self.presentAlert(message: "Error solving service area: \(error.localizedDescription)")
            } else {
                //add resulting polygons as graphics to the overlay
                //since we are using `geometryAtOVerlap` as `dissolve` and the cutoff values
                //are the same across facilities, we only need to draw the resultPolygons at
                //facility index 0. It will contain either merged or multipart polygons
                if let polygons = result?.resultPolygons(atFacilityIndex: 0) {
                    for index in polygons.indices {
                        let polygon = polygons[index]
                        let fillSymbol = self.serviceAreaSymbol(for: index)
                        let graphic = AGSGraphic(geometry: polygon.geometry, symbol: fillSymbol, attributes: nil)
                        self.serviceAreaGraphicsOverlay.graphics.add(graphic)
                    }
                }
            }
        }
    }
    
    @IBAction private func clearAction() {
        //remove all existing graphics in service area and facilities graphics overlays
        self.serviceAreaGraphicsOverlay.graphics.removeAllObjects()
        self.facilitiesGraphicsOverlay.graphics.removeAllObjects()
        self.barriersGraphicsOverlay.graphics.removeAllObjects()
    }
    
    // MARK: - AGSGeoViewTouchDelegate
    
    func geoView(_ geoView: AGSGeoView, didTapAtScreenPoint screenPoint: CGPoint, mapPoint: AGSPoint) {
        if segmentedControl.selectedSegmentIndex == 0 {
            //facilities selected
            let graphic = AGSGraphic(geometry: mapPoint, symbol: nil, attributes: nil)
            self.facilitiesGraphicsOverlay.graphics.add(graphic)
        } else {
            //barriers selected
            let bufferedGeometry = AGSGeometryEngine.bufferGeometry(mapPoint, byDistance: 500)
            let graphic = AGSGraphic(geometry: bufferedGeometry, symbol: nil, attributes: nil)
            self.barriersGraphicsOverlay.graphics.add(graphic)
        }
    }
    
    // MARK: - Navigation
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "ServiceAreaSettingsSegue" {
            let controller = segue.destination as! ServiceAreaSettingsViewController
            controller.presentationController?.delegate = self
            controller.preferredContentSize = CGSize(width: 300, height: 200)
            controller.delegate = self
            controller.firstTimeBreak = self.firstTimeBreak
            controller.secondTimeBreak = self.secondTimeBreak
        }
    }
    
    // MARK: - ServiceAreaSettingsViewControllerDelegate
    
    func serviceAreaSettingsViewController(_ serviceAreaSettingsViewController: ServiceAreaSettingsViewController, didUpdateFirstTimeBreak timeBreak: Int) {
        self.firstTimeBreak = timeBreak
    }
    
    func serviceAreaSettingsViewController(_ serviceAreaSettingsViewController: ServiceAreaSettingsViewController, didUpdateSecondTimeBreak timeBreak: Int) {
        self.secondTimeBreak = timeBreak
    }
    
    // MARK: - UIAdaptivePresentationControllerDelegate
    
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
}
