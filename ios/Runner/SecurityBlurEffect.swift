//
//  SecurityBlurEffect.swift
//  Runner
//
//  Created by 三夜 on 2021/2/9.
//

import Foundation
import UIKit


public class SecurityBlurEffect {
     class func addBlurEffect(to window: UIWindow?){
        guard let window = window else { return }
        
        let blurEffect = UIBlurEffect(style: UIBlurEffect.Style.regular)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        
        blurEffectView.tag = 19999
        blurEffectView.alpha = 0.99
        blurEffectView.frame = window.bounds
    
        window.backgroundColor = UIColor.clear
    
        window.addSubview(blurEffectView)
        
        
    }
    
    
    class func removeBlurEffect(from window: UIWindow?){
        guard let window = window else { return }
        
        let subViews = window.subviews;
        
        for  view in subViews {
            if view.tag == 19999 {
                if  view is UIVisualEffectView {
                    UIView.animate(withDuration: 0.3, animations: {
                        view.removeFromSuperview()
                    })
                }
            }
        }
    }
}
