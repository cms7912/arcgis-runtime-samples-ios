// Copyright 2016 Esri.
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

class MMLLayersViewController: UITableViewController {
    
    /// A change handler that calls back with the operational layers.
    var onChange: (([AGSLayer]) -> Void)?
    
    /// Every layer on the map or that could be added to the map.
    var removedLayers: [AGSLayer] = []
    /// The layers attached to the map in back-to-front order.
    var operationalLayers: [AGSLayer] = []
    
    /// The operational layers in reverse order so the topmost layer is first.
    private var operationalLayersForTable: [AGSLayer] {
        set {
            if newValue != operationalLayersForTable {
                operationalLayers = newValue.reversed()
                // the user edited the layers in the table so run the change handler
                onChange?(operationalLayers)
            }
        }
        get{
            return operationalLayers.reversed()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // enable the editing UI
        tableView.isEditing = true
    }
    
    /// A convenience type for the table view sections.
    private enum Section: Int {
        case operational, removed
        
        var label: String {
            switch self {
            case .operational:
                 return "Operational Layers"
            case .removed:
                 return "Removed Layers"
            }
        }
    }
    
    //MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .operational:
            return operationalLayersForTable.count
        case .removed:
            return removedLayers.count
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.label
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LayerCell", for: indexPath)
        
        let layerForIndexPath: AGSLayer = {
            switch Section(rawValue: indexPath.section)! {
            case .operational:
                return operationalLayersForTable[indexPath.row]
            case .removed:
                return removedLayers[indexPath.row]
            }
        }()
        cell.textLabel?.text = layerForIndexPath.name
        return cell
    }

    //MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        switch Section(rawValue: indexPath.section)! {
        case .operational:
            return .delete
        case .removed:
            return .insert
        }
    }
    
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return Section(rawValue: indexPath.section) == .operational
    }
    
    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        
        if Section(rawValue: sourceIndexPath.section) == .operational,
            Section(rawValue: proposedDestinationIndexPath.section) == .operational {
            // only allow reordering within the operational layers section
            return proposedDestinationIndexPath
        }
        return sourceIndexPath
    }
    
    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        // update the order of layers in the array
        
        if destinationIndexPath != sourceIndexPath {
            operationalLayersForTable.swapAt(sourceIndexPath.row, destinationIndexPath.row)
        }
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        switch editingStyle {
        case .delete:
            // move the layer from the operational layers to the removed layers
            let layer = operationalLayersForTable.remove(at: indexPath.row)
            removedLayers.append(layer)
           
            // update the table
            tableView.performBatchUpdates({
                // delete the row
                tableView.deleteRows(at: [indexPath], with: .automatic)
                let newIndexPath = IndexPath(row: removedLayers.count-1, section: 1)
                // insert the new row
                tableView.insertRows(at: [newIndexPath], with: .automatic)
            })
            
        case .insert:
            // move the layer from the removed layers to the operational layers
            let layer = removedLayers.remove(at: indexPath.row)
            operationalLayersForTable.insert(layer, at: 0)
            
            // update the table
            tableView.performBatchUpdates({
                // delete the row
                tableView.deleteRows(at: [indexPath], with: .fade)
                let newIndexPath = IndexPath(row: 0, section: 0)
                // insert the new row
                tableView.insertRows(at: [newIndexPath], with: .fade)
            })
        case .none:
            break
        }
    }

}
